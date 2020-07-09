---
layout: post
title: Deconstructing Apollo Part 1&#58; The Cache
image: '/images/tech/cache.jpg'
category: Tech
tags: [JavaScript, Apollo, GraphQL, Cache]
---

A look at the new features of the Apollo 3 Cache and how it works under the hood.

<!--halt-->

# Apollo 3 Cache

The Apollo 3 release cut early June and comes with some exciting new cache features:

* Type Policies
* Modify API
* Cache Eviction

To help us use these APIs, it's good to first examine how the cache works.

## Interacting with the Cache

<img src="{{ site.baseurl }}/images/tech/apollo-cache.png" />

Cache operations are funneled through 4 key layers from the ApolloClient to the underlying data store.

Below we will examine how the cache works by stepping through a `writeQuery` operation.

## Layer 1: The Client

This is highest and most familiar layer for Apollo users. Users call `writeQuery` directly on the client passing in a query and data:

```ts
apolloClient.writeQuery({
  query: gql`{
    employees {
      data {
        id
        employee_name
        employee_age
      }
    }
  }`,
  data: {
    employees: {
      __typename: "EmployeesResponse",
      data: [employee, employee2],
    },
  }
});
```

> Note: No `id` field is required if we're writing to a query instead of a normalized entity, which we'll talk about more later.

> Note: Every property in our data object that we want persisted must also be listed in the query, otherwise it'll not be written.

## Layer 2: The Cache

The client relays the `writeQuery` invocation to the cache, calling `cache.writeQuery`. By default, the client uses the Apollo `InMemoryCache`, although
users can pass in their own cache to the client as along as it conforms to the base `cache` specification.

The cache is the last layer that exposes a public interface, with tools for performing eviction via `cache.evict` and cache modification via `cache.modify`.

It relays the data from `writeQuery` and calls the underlying `cache.write` API which hands the query data off to the `StoreWriter` module.

## Layer 3: The StoreWriter

The StoreWriter's `writeToStore` API is passed the query data and begins processing it into the `EntityStore`, the final layer which actually stores
cached data.

The `writeToStore` API marshalls data and tokenizes the query and then hands it off to `StoreWriter.processSelectionSet`, a recursive function that goes through the selection set
of the tokenized query and processes fields in a depth-first pattern.

If a field policy exists for the field processed that is being updated, it will run the type policy for that field at this time, passing in the existing and incoming values.

It then calls the `EntityStore.merge` API with the merged or raw incoming value in order to persist it in the data store.

## Layer 4: The EntityStore

The EntityStore is the underlying data store of the cache. It is a class which stores the actual data that gets read and written to and is created by the cache layer. It contains the core private APIs for manipulating and reading stored data.

The entity store structures its data into two groups:

1. Normalized data entities
2. Queries

## Our query

Let's take another look at our query and see how the cache models that data after it is written:

```ts
apolloClient.writeQuery({
  query: gql`{
    employees {
      data {
        id
        employee_name
        employee_age
      }
    }
  }`,
  data: {
    employees: {
      __typename: "EmployeesResponse",
      data: [employee, employee2],
    },
  }
});
```

## EntityStore Structure

```ts
{
  ROOT_QUERY: {
    employees: {
      __typename: 'EmployeesResponse',
      data: [{ __ref: 'Employee:1' }, { __ref: 'Employee:2' }]
    }
  },
  "Employee:1": {
    __typename: 'Employee',
    id: 1,
    employee_name: 'First Employee',
    employee_age: 25,
  },
  "Employee:2": {
    __typename: 'Employee',
    id: 2,
    employee_name: 'Second Employee',
    employee_age: 35
  },
}
```

All queries are stored under `ROOT_QUERY` and the structure looks pretty similar to the data we wrote. The big difference is that now the data array of Employee entities
is by reference instead of value.

## Cache Normalization

The Apollo cache uses a normalization strategy for types with identifiable ID fields or composite keys. Anything with an ID is stored by reference in queries. This is useful when entities
referenced by queries change, since the queries do not need to be updated.

It makes it more challenging, however, when entities are created or deleted since queries do not automatically include or remove these entities.

While cache normalization might seem like an implementation detail, in Apollo 3 it is important to understand these data structures, since a lot of the public API requires knowledge of references.

## Type Policies

In the `writeQuery` example we followed through how entities get written into the cache. Apollo 3 type policies allow us to define per-field policies for fine-grained control of exactly what gets written.

For example, let's use a type policy to control how employee names are stored in the cache:

```ts
const cache = new InMemoryCache({
  typePolicies: {
    Employee: {
      fields: {
        employee_name: {
          merge(existing, incoming, options) {
            return incoming.split(' ')[0];
          }
        }
      }
    }
  }
```

Here we've defined a field policy on the Employee type for how its name field should be merged into the cache. When the StoreWriter passes the data for the Employee entity to the EntityStore, it will first run the fields through the existing field policies and pass that data down to the data store.

## Type Policy Options

```ts
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      employees: {
        merge(existing, incoming, { readField, toReference }) {
          return {
            ...existing,
            data: existing.data.filter(
              employeeRef => readField('employee_age', existing) >= 18
            )
          }
        }
      }
    }
  }
```

In this example we reject storing any employees under the age of 18 in our query, since they're not of working age. The entities read and written in these policies are refs,
so we need to use `readField` to access fields out of the cache for the ref and `toReference` to write entities down into the cache.

## Cache.Modify

Apollo 3 introduces a new API for manipulating data in the cache called `modify`. It is similarly structured to the merge API in the field policy we saw above and operates on cache references.
If we did not have the field policy from the previous example in place, we could retroactively remove the entity from the query using modify:

```ts
cache.modify({
  fields: {
    employees(existing, { readField, toReference }) => {
      return {
        ...existing,
        data: existing.data.filter(
          employeeRef => readField('employee_age', existing) >= 18
        )
      }
    }
  }
});
```

Modify is also the API of choice for updating a query after a mutation.

## Modify vs read/write 

In Apollo 2, the common update pattern after a mutation was to write something like:

```ts
function AddEmployee() {
  const [addEmployee] = useMutation(
    ADD_EMPLOYEE,
    {
      update(cache, { data: { addEmployee } }) {
        const currentEmployees = cache.readQuery({
          query: GET_EMPLOYEES
        });

        cache.writeQuery({
          query: GET_EMPLOYEES,
          data: [
            ...currentEmployees,
            addEmployee
          ]
        })
      }
    }
  );
}
```

This is problematic because not only do you need to do a verbose read/write pattern, but if your GET_EMPLOYEES query has fewer fields specified than your ADD_EMPLOYEE
query for example, then you would lose data when writing!

The modify API makes it easier to perform updates like this:

```ts
function AddEmployee() {
  const [addEmployee] = useMutation(
    ADD_EMPLOYEE,
    {
      update(cache, { data: { addEmployee } }) {
        cache.modify({
          employees(existing, { toReference }) {
            return [...existingTodos, toReference(addEmployee)]
          }
        });
      }
    }
  );
}
```

But since it operates on references, it requires more knowledge of how the cache works to be done correctly. A user needs to know that the new employee created must be turned into a reference in order to be stored.

### Eviction API

If all we want to do is remove an entity from the store instead of modifying it, we can use the new eviction API.

```ts
function deletEmployee() {
  const [deleteEmployee] = useMutation(
    DELETE_EMPLOYEE,
    {
      update(cache, { data: { deleteEmployee } }) {
       cache.evict({ id: 'ROOT_QUERY', fieldName: 'employees' });
      }
    }
  );
}
```

Here we evict the employees query we had cached when deleting an employee. This is useful in the case that you know a mutation invalidates a stored query and need to remove it in response.

> Note: Here again we can choose to omit the `id` in the case of operating on the `ROOT_QUERY` as it is defaulted.

Evicting the `employees` query will remove all variants of the `employees` query regardless of variables.
If the desired behaviour is to only evict a query stored for a particular set of variables, they can be passed in:

```ts
cache.evict({ fieldName: 'employees', args: { country: 'US' }});
```

Now only queries that were stored with *exactly* the variables passed in as the arguments to the eviction will be evicted. Passing in a subset of variables will not work, it must be an exact match.

We can also easily remove particular normalized entities from the cache if we know they're no longer being used:

```ts
cache.evict({ id: 'Employee:1' });
```

If we want to remove all unused entities from the cache we can similarly call the `gc` garbage collection API:

```ts
cache.gc();
```

The garbage collection API will remove all entities that are not retained, where retained means that the entity has had `cache.retain` called on it more times than it has been released via `cache.release` or if it is referenced either directly or indirectly by a such a retained entity. The `ROOT_QUERY` object or a normalized entity written directly such as with `writeFragment` will automatically have `retain` called on it. 

`gc` will then recursively search through the values of retained entities to find other entities referenced by them and mark those to be kept as well. All entities not reached by this process will then be removed from the entity store.

## That's all for now!

This has been a first dive into how the cache works and how we can use that knowledge to better take advantage of the new features exposed in Apollo 3. I'm excited to keep exploring the new features Apollo 3 has to offer. In part 2 we'll take a look at how Apollo uses optimistic mutations to provide instant user feedback.
