---
layout: post
title: Apollo Normalized Collections
image: '/images/tech/normalized-collections.jpg'
category: Tech
tags: [Apollo, GraphQL]
---

A guide for querying collections by type in Apollo Client.

<!--halt-->

## [Type Policies Refresher](#refresher)

In a [past post](https://danreynolds.ca/tech/2020/11/28/Redux-To-Apollo-Accessing-Data/#canonical-fields) we explored how to create Apollo type policies to query for derived data in Apollo similarly to Redux selectors. To quickly refresh ourselves on the topic, let's walk through a quick example. We could start with a query like this:

```js
query GetEmployees {
  employees {
    id
    name
    role
    team
  }
}
```

When this query is executed, it will store data in the Apollo cache in the following shape:

```js
{
  'Employee:1': {
    __typename: 'Employee',
    id: 1,
    name: 'Alice',
    role: 'Manager',
    team: 'Banking',
  },
  'Employee:2': {
    __typename: 'Employee',
    id: 1,
    name: 'Bob',
    role: 'Senior Developer',
    team: 'Investments',
  },
  ROOT_QUERY: {
    employees: {
      __typename: 'EmployeesResponse',
      data: [
        { __ref: 'Employee:1' },
        { __ref: 'Employee:2' },
      ]
    },
  }
}
```

If we wanted to then query for all of the employees that exist in the cache, we can see that they live under the `employees` field we queried for and could write a query like this in a React component (or frontend lib of your choice):

```js
const { data: employeesResponse } = useQuery(
  gql`
    query GetEmployees {
      employees {
        id
      }
    }
  `,
  {
    fetchPolicy: 'cache-only',
  }
);

const employees = employeesResponse?.data ?? [];
```

Now we will be able to access all of our employees from the cache. To simplify the developer experience further, we can create a type policy that reads the employees field for us:

```js
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        readEmployees: {
          read(employees, { readField }) {
            return readField('employees')?.data ?? [];
          },
        },
      },
    },
  },
});
```

The `readEmployees` type policy will read the `employees` field on the `ROOT_QUERY` and access its list of employees, defaulting it to an empty array. This is a simple little abstraction around having to read the `employees` field and do that `data` property access and array defaulting each time we query for it on the client. Now our query in our component can look like this:

```js
const { data: employees } = useQuery(
  gql`
    query GetEmployees {
      readEmployees @client {
        id
      }
    }
  `,
);
```

> Note the usage of the `@client` directive that must be used when querying for fields that are defined on the client with type policies.

We call fields like `employees` a *canonical field*, defined as a field that represents the entire collection of a particular type on the client from which custom filters and views of that data are derived. These canonical fields are useful when we need access a list of all entities of a particular type, such as on a page where we want to display a list of all employees at the company.

While canonical fields partially solve the problem of accessing collections of a given type, they come with some negative developer overhead. This is illustrated in the scenario where a new employee is added to the company via a mutation on the client.

With a GraphQL schema that looks like this:

```gql
type CreateEmployeeResponse {
  employee: Employee!
}

extend type Mutation {
  createEmployee(name: String!): CreateEmployeeResponse
}
```

We can then execute a mutation to create an employee:

```js
useMutation(
  gql`
    mutation CreateEmployee($name: String!) {
      createEmployee(
        name: $name
      ) {
        employee {
          id
          name
        }
      }
    }
  `,
  {
    variables: {
      name: 'Charlie',
    },
  },
);
```

The `createEmployee` mutation will go create the employee in our database on the server, and then return a `CreateEmployeeResponse` response with the newly created `Employee` object. The updated cache would then look like this:

```js
{
  'Employee:1': {
    __typename: 'Employee',
    id: 1,
    name: 'Alice',
    role: 'Manager',
    team: 'Banking',
  },
  'Employee:2': {
    __typename: 'Employee',
    id: 1,
    name: 'Bob',
    role: 'Senior Developer',
    team: 'Investments',
  },
  'Employee:3': {
    __typename: 'Employee',
    id: 1,
    name: 'Charlie',
  },
  ROOT_QUERY: {
    employees: {
      __typename: 'EmployeesResponse',
      data: [
        { __ref: 'Employee:1' },
        { __ref: 'Employee:2' },
      ]
    },
  },
  ROOT_MUTATION: {
    "createEmployee({name:'Charlie'})": {
      __typename: 'CreateEmployeeResponse',
      data: {
        employee: { __ref: 'Employee:3' }
      }
    }
  },
}
```

We can see that the new employee was added to the cache and that it exists as a normalized entity. The problem though is that nothing has told the cache to update our canonical `employees` field to include this new employee. If a user were to navigate to a page showing a list of all our employees using the `readEmployees` type policy, it would not show our new employee Charlie.

There are a couple ways to fix this problem:

1. **Re-query the `employees` field**: We can always run the `GetEmployees` query again to hit the server and get back an updated list of employees. The updated list would be written to the `employees` field in the cache and all of our UI would refresh to include the new employee. While this approach works, having to hit the network every time we need to change the `employees` field on the client is a heavy operation that shouldn't be necessary.

2. **Manually update the `employees` field**: The alternative approach would be to tell our employees field that it is out of date and update it to include the new employee. We could do this with a call to `cache.modify` like this after finishing our mutation:

```js
useMutation(CREATE_EMPLOYEE, {
  update(cache, { data: { createEmployee } }) {
    cache.modify({
      fields: {
        employees(existingEmployees = [], { readField }) {
          const newEmployeeRef = cache.writeFragment({
            data: addComment,
            fragment: gql`
              fragment NewEmployee on Employee {
                id
                name
              }
            `
          });
          return [...existingEmployeeRefs, newEmployeeRef];
        }
      }
    });
  }
});
```

Now our canonical `employees` field is kept in sync with our `createEmployee` mutation and everywhere we rely on using it to access our full list of employees will automatically update when a new employee is created.

While this pattern works, it puts a lot of burden on developers to keep the canonical field in sync with all the other operations that could affect the canonical collection of entities. Let's highlight some of the main problems with this approach: 

1. **It causes bugs**: There may be many operations that affect the collection of entities for a type like `employees` and we would need to write manual `cache.modify` handlers for each of them to keep the field in sync. This can easily cause bugs where a developer misses updating the canonical field after a mutation, causing it to no longer reflect the complete list of entities of a type in the cache.

2. **Scalability**: This approach also requires us to write **a lot** of type policies, since we would need to write one for each canonical field like we did with the `readEmployees` type policy, as well as any derived sets of data. One example data derivation would be if we wanted to read a list of employees from a certain team. The type policy for that query could look like this:

```js
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        readEmployees: {
          read(employees, { readField }) {
            return readField('employees')?.data ?? [];
          },
        },
        readBankingTeam: {
          read(_existingBankingTeam, { readField }) {
            return readField('readEmployees').filter(employeeRef => {
              const employeeTeam = readField('team', employeeRef);
              return employeeTeam === 'Banking';
            });
          }
        },
      },
    },
  },
});
```

The banking employees query uses our canonical field and filters it down to the matching set of employees. While this works, having to manually write a new type policy every time we want to filter our collections can bloat our codebase over time.

3. **Assumes there is a canonical field**: It might be the case that there actually isn't a single query like `employees` that we can use as our canonical field. For instance, if the query for the list of employees is paginated, each page would be stored under separate fields on the root query like this:

```js
{
  'Employee:1': {
    __typename: 'Employee',
    id: 1,
    name: 'Alice',
    role: 'Manager',
    team: 'Banking',
  },
  'Employee:2': {
    __typename: 'Employee',
    id: 1,
    name: 'Bob',
    role: 'Senior Developer',
    team: 'Investments',
  },
  ...
  ROOT_QUERY: {
    "employees({page:1})": {
      __typename: 'EmployeesResponse',
      data: [
        { __ref: 'Employee:1' },
        { __ref: 'Employee:2' },
      ]
    },
    "employees({page:2})": {
      __typename: 'EmployeesResponse',
      data: [
        { __ref: 'Employee:3' },
        { __ref: 'Employee:4' },
      ]
    },
  }
}
```

In this scenario, there isn't a single field that we can use as a canonical field for all employee entities in the cache. We could try to create one by appending to a manually synced `employees` field whenever we get back a new page or use a new `employees` type policy that aggregates the different pages together under the hood, but neither of those options are ideal since they both require a lot of developer effort to maintain and can lead to bugs.

## [Normalized Collections](#normalized-collections)

To address this problem, we eventually came up with an approach that adds normalized collections to the Apollo Cache by default in the [Apollo Cache policies](https://github.com/NerdWalletOSS/apollo-cache-policies) library.

To use collections, we instantiate the `InvalidationPolicyCache` and indicate that we want it enabled:

```js
cache = new InvalidationPolicyCache({
  enableCollections: true,
});
```

We can then make queries like normal and take a look at how these new collections are stored in the cache:

```js
const { data: employeesResponse } = useQuery(
  gql`
    query GetEmployees {
      employees {
        id
      }
    }
  `,
  {
    fetchPolicy: 'cache-only',
  }
);
```

```js
{
  "CacheExtensionsCollectionEntity:Employee": {
    __typename: 'CacheExtensionsCollectionEntity',
    id: 'Employee',
    data: [
      { __ref: employee.toRef() }, { __ref: employee2.toRef() }
    ],
  },
  {
  'Employee:1': {
    __typename: 'Employee',
    id: 1,
    name: 'Alice',
    role: 'Manager',
    team: 'Banking',
  },
  'Employee:2': {
    __typename: 'Employee',
    id: 1,
    name: 'Bob',
    role: 'Senior Developer',
    team: 'Investments',
  },
  ROOT_QUERY: {
    __typename: "Query",
    employees: {
      __typename: "EmployeesResponse",
      data: [{ __ref: employee.toRef() }, { __ref: employee2.toRef() }],
    },
  },
}
```

In addition to the normalized `Employee` entities we saw before, there is a new `CacheExtensionsCollectionEntity` collection entity that contains a list of references to every employee that has been written to the cache. These normalized collections can then be easily accessed with some new APIs:

* `useFragmentWhere`: A new React hook for filtering a collection of entities by type
* `cache.readReferenceWhere`: A cache API that returns a list of references in the cache for a particular type and filter
* `cache.readFragmentWhere`: The collection filter equivalent of the existing `cache.readFragment` API
* `cache.watchFragmentWhere`: The collection filter equivalent of the existing `cache.watchFragment` API

### [useFragmentWhere](#useFragmentWhere)

The `useFragmentWhere` API allows us to query for a filtered collection of entities by type. It takes two arguments, a GraphQL fragment for the fields to read from the type and an object of all the fields to filter by.

Now our client can access all employees of a particular team in one operation without having to manually maintain any canonical fields or write new type policies:

```js
import { useFragmentWhere } from '@nerdwallet/apollo-cache-policies';

const { data } = useFragmentWhere(
  gql`
    fragment EmployeesByTeam on Employee {
      id
      name
    }
  `,
  {
    team: 'Banking',
  }
)
```

If we just want to retrieve all entities in the cache for a particular type, we can omit the filter altogether:

```js
import { useFragmentWhere } from '@nerdwallet/apollo-cache-policies';

const { data } = useFragmentWhere(
  gql`
    fragment AllEmployees on Employee {
      id
      name
    }
  `
)
```

The `useFragmentWhere` API will automatically update the component just like `useQuery` when the employees that match the filter change, including when a new employee that matches the filter criteria is added to the cache.

### Using Collections in Type Policies

While `useFragmentWhere` gives us access to collections of entities in a component, we still want to be able to access collections from our type policies. Some scenarios where we would want to do this include:

1. **Common filters**: If we often need to filter a list of employees by team, it would be nice to be able to reuse that code rather than having to write the same `useFragmentWhere` each time. A single `bankingTeam` type policy is a good choice for letting clients query that data across the application.

2. **Complex filters**: Certain filters might not be possible with the `useFragmentWhere` API, such as filtering employees above a certain age.

Let's take a look at how we'd approach both of these scenarios with the new `readReferenceWhere` API.

### [Cache.readReferenceWhere](#readReferenceWhere)

Normalized collections can be accessed in type policies using the new `cache.readReferenceWhere` API. `readReferenceWhere` will return a list of references for a given type and filter. Let's reconstruct our `readBankingTeam` type policy using collections:

```js
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        readBankingTeam: {
          read(_existingBankingTeam, { cache }) {
            return cache.readReferenceWhere(
              {
                __typename: 'Employee',
                filter: {
                  team: 'Banking',
                },
              }
            );
          }
        },
      },
    },
  },
});
```

The `readBankingTeam` type policy ends up being a lot simpler to work with. We no longer needs to read from a manually maintained `employees` field and we don't have to loop over each reference calling `readField` to compare properties.

If we wanted to write our type policy for employees above a certain age, we could similarly use `readReferenceWhere` to access our normalized collection and perform a complex filter:

```js
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        employeesAboveAge: {
          read(_existingEmployeesAboveAge_, { cache, args, readField }) {
            const employees = cache.readReferenceWhere({
              __typename: 'Employee',
            });

            return employees.filter((employeeRef) => {
              const age = readField('age', employeeRef);

              return age && age >= args.age;
            });
          }
        },
      },
    },
  },
});
```

## [How it Works](#howitworks)

Normalized collections allow us to simplify how we access and manage collections of types in the cache. While they can seem pretty magical, they are built using the existing tools available to us in Apollo Client.

When you use `useFragmentWhere` to subscribe to a filtered list of a collection, it dynamically constructs a new type policy with the name of the fragment you provide:

```js
if (!policies.getFieldPolicy('Query', fragmentName)) {
  policies.addTypePolicies({
    Query: {
      fields: {
        [fragmentName]: {
          read(_existing) {
            return cache.readReferenceWhere({
              __typename,
              filter,
            });
          }
        }
      }
    }
  });
}
```

It then uses the `readReferenceWhere` we looked at earlier to retrieve the list of matching references for your filter. Since it's a type policy just like the normal ones we write, it can be queried for like any other field.

Once a new type policy has been added, it then generates a query for that field and calls  `useQuery` to subscribe to the query:

```js
export default function useFragmentWhere<FragmentType>(fragment: DocumentNode, filter?: FragmentWhereFilter<FragmentType>) {
  const context = useContext(getApolloContext());
  const client = context.client;
  const cache = client?.cache as unknown as InvalidationPolicyCache;

  const query = useOnce(() => buildWatchFragmentWhereQuery({
    filter,
    fragment,
    cache,
    policies: cache.policies,
  }));

  return useQuery(query, {
    fetchPolicy: 'cache-only',
  });
}
```

Since it uses `useQuery` under the hood, it will automatically update when the data it cares about in the cache changes just like any other query we provide to `useQuery`. If you're interested in learning more, feel free to check out the pull request introducing this change [here](https://github.com/NerdWalletOSS/apollo-cache-policies/pull/33).

## Feedback Welcome

We'd love to hear about whether these APIs are useful in your Apollo workflows and if there are any additional use cases or APIs that we could address to make working with normalized collections easier. Feel free to leave comments on the PR linked above or create new issues on the GitHub repo. Happy querying!
