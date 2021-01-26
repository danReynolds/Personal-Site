---
layout: post
title: Redux-To-Apollo-Middlewares-and-Side-Effects
image: '/images/tech/filter-data.jpg'
category: Tech
tags: [JavaScript, Apollo, GraphQL, Cache, Invalidation, Policies]
---

Moving past part 1 where we talked about data access, this second deep dive looks at handling data mutation
and side-effects when moving from Redux to Apollo.

<!--halt-->

# Background

In part 1 of this series, we examined how we can use Apollo type policies to accomplish effective client-side data access like we had with our Redux selectors. Now that we know how to access the data in our Apollo application, we need to explore the ways to manage the lifecycle of that data. This is especially interesting for client-side data
that is highly relational, 

The Apollo 3 cache is a great tool for managing the data returned by your application's GraphQL queries. As a normalized data cache,
it stores the entities returned by queries by reference in the cache. A query to fetch a list of employees and their messages might look like this:

```typescript
query GetEmployees {
  employees {
    data {
      id
      name
      role
      team
    }
  }
  teams {
    data {
      id
      name
      manager
      members {
        id
      }
    }
  }
}
```

would be represented in the cache like this:

```typescript
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
    id: 2,
    name: 'Bob',
    role: 'Senior Developer',
    team: 'Investments',
  },
  'Employee:3': {
    __typename: 'Employee',
    id: 3,
    name: 'Charlie',
    role: 'Engineering Manager',
    team: 'Investments',
  },
  {
    'Team:1': {
      __typename: 'Team',
      id: 1,
      name: 'Banking Team',
      manager: {
        __ref: 'Employee:1',
      },
      members: [
        { __ref: 'Employee:1' }
      ]
    }
  },
  {
    'Team:2': {
      __typename: 'Team',
      id: 2,
      name: 'Investments Team',
      manager: {
        __ref: 'Employee:3',
      },
      members: [
        { __ref: 'Employee:2' }
        { __ref: 'Employee:3' }
      ]
    }
  }
  ROOT_QUERY: {
    employees: {
      __typename: 'EmployeesResponse',
      data: [
        { __ref: 'Employee:1' },
        { __ref: 'Employee:2' },
        { __ref: 'Employee:3' },
      ]
    },
    teams: {
      __typename: 'TeamsResponse',
      data: [
        { __ref: 'Team:1' },
        { __ref: 'Team:2' },
      ]
    }
  }
}
```

With relational data like this, it can be a challenge to manage it's lifecycle in the cache. Let's look at a typical example where we'd need to handle cache relationships.

## Updating the cache after a mutation

If an employee were to leave the company, we'd need to get them to stop showing up in our cached employees and teams queries. The first tool we can turn to is the Apollo 3 [evict API](https://www.apollographql.com/docs/react/caching/garbage-collection/#cacheevict).

When Charlie, the investment team manager at our company and employee number in our cache, decides to leave, we run a mutation to delete him from the system. We then define a custom update handler that evicts his employee entity from the cache:

```typescript
// Charlie's employee ID
const deletedEmployeeId = '3';

const [deleteEmployee] = useMutation(DELETE_EMPLOYEE, {
  variables: {
    employeeId: deletedEmployeeId,
  }
  update(cache) {
    cache.evict(`Employee:${deletedEmployeeId}`);
  }
});
```

Charlie's normalized employee entity has now been removed from the cache. We're all good now right? Well, not quite.

First we need to understand what happens to our cached `employees` and `teams` queries that contained references to the evicted employee. Apollo calls these references to normalized entities that are no longer in the cache *dangling references*.

## Leave-and-filter approach

Ideally what I would expect to happen in that case is for Apollo to traverse its cached queries and remove the invalid references to the evicted entity. In reality, they remain in the cache, and Apollo makes note of this in their documentation:

> When an object is evicted from the cache, references to that object might remain in other cached objects. Apollo Client preserves these dangling references by default, because the referenced object might be written back to the cache at a later time. This means the reference might still be useful.

Because the references might become valid later, Apollo errs on the side of keeping them. This could cause problems though, as what happens when parts of our application try to read cached queries that contain dangling references? To solve this problem, Apollo introduced a `canRead` utility you can access in your type policies to filter out dangling references:

```typescript
  typePolicies: {
    EmployeesResponse: {
      fields: {
        data(employeesData, { canRead }) {
          return employeesData.filter(employeeRef => canRead(employeeRef));
        },
      },
    },
    Team: {
      fields: {
        manager(managerRef, { canRead }) {
          return canRead(managerRef) ? managerRef : null;
        },
        members(membersData, { canRead }) {
          return membersData.filter(employeeRef => canRead(employeeRef));
        },
      },
    },
  },
})
```

This works, but having to define custom type policies for reading all the fields that could contain dangling references is a bit of a pain, so instead, the cache will **automatically** do this for you for all **array** fields in the cache.

Problem solved? Unfortunately no, we still have **two** big problems with this approach.

Since Charlie was an engineer manager, a reference to his employee entity existed not only in the array of team members, but also in the manager field, so we would still need to define our `manager` custom field policy as well as any others that reference evicted entities directly.

The second and even more egregious problem is that while this "leave them in and then filter them out" approach works for the next time we try to read these cached queries, nothing has caused our existing subscriptions in the UI for fields like `employees` or `teams` to re-execute and until they are re-run, they will still contain Charlie's employee reference!

So how can we tell our existing UIs to update after an entity is evicted? We'll need to explore an alternative approach.

## Evict-on-Write approach

Instead of leaving the dangling references in the cache, this time we'll explicitly remove the deleted employee reference. This will require us to:

1. Remove the employee from the cached `employees` query
2. Remove the employee from any `Team`normalized entity that contains a reference to that employee
3. Remove the `manager` field from any `Team` that had that employee as their manager
4. Remove the employee's normalized entity from the cache

Our update handler would then look like this:

```typescript
const deletedEmployeeId = '3';

const [deleteEmployee] = useMutation(DELETE_EMPLOYEE, {
  variables: {
    employeeId: deletedEmployeeId',
  }
  update(cache) {
    // 1. Remove the employee from the cached `employees` query
    cache.modify({
      fields: {
        employees(employeesResponse, { readField }) {
          const employees = employeesResponse.data;
          const remainingEmployees = employees
            .filter(employeeRef => readField('id', employeeRef) !== deletedEmployeeId);

          return {
            ...employeesResponse,
            data: remainingEmployees
          }
        },
      }
    });

    cache.modify({
      id: 'Team:2',
      fields: {
        // 2. Remove the employee from the `Team:2` normalized entity that contains a reference to that employee
        members(teamMembers, { readField }) {
          const remainingTeamMembers = employees
            .filter(teamMemberRef => readField('id', teamMemberRef) !== deletedEmployeeId);

          return remainingTeamMembers;
        },
        // 3. Remove the `manager` field from any `Team` that had that employee as their manager
        manager(existingManager) {
          return null;
        }
      }
    });

    // 4. Remove the employee's normalized entity from the cache
    cache.evict(`Employee:${deletedEmployeeId}`);
  }
});
```

The [modify API](https://www.apollographql.com/docs/react/caching/cache-interaction/#cachemodify) allows us to alter the value of any field in the cache, and we can use it to remove our deleted employee reference from both the cached `employees` query and the normalized `Team:2` entity under its `members` and `manager` fields. We then remove the deleted employee normalized entity same as we did before with the `evict` API.

Now any queries that had accessed the `employees` field or the `members` or `manager` of the `Team:2` entity will re-execute and our UI will correctly update to remove our deleted employee.

While this works, it has a couple issues:

1. We're co-locating a lot of business logic with our `delete` mutation in our component. Ideally our component should just be able to call a delete mutation and not have to worry about removing entities from a variety of places in our cache.

This isn't too hard of an issue to solve, as we could always abstract the update behavior to a helper function and call it whereever we delete employees. But it would be nice if there was a more systematic approach.

2. How did we know that `Team:2` was the correct team to remove Charlie's `Employee:3` entity from? We often won't have context like that when deleting entities, and we'd somehow need to iterate through all possible teams and see if any of them included it. 


To solve both these problems, at our company we've written a library called [Apollo invalidation policies](https://github.com/NerdWalletOSS/apollo-invalidation-policies).

## Apollo invalidation policies

The [Apollo invalidation policies](https://github.com/NerdWalletOSS/apollo-invalidation-policies) library is an extension of the Apollo 3 cache that provides a framework for managing the lifecycle and relationships of cache data through the new concept of invalidation policies.

Like type policies, invalidation policies are declared for typenames of your GraphQL schema and form relationships between different types:

```typescript
import { InvalidationPolicyCache } from 'apollo-invalidation-policies';
const cache = new InvalidationPolicyCache({
  typePolicies: {...},
  invalidationPolicies: {
    timeToLive: Number;
    renewalPolicy: RenewalPolicy;
    types: {
      Typename: {
        timeToLive: Number,
        renewalPolicy: RenewalPolicy,
        PolicyEvent: {
          Typename: (PolicyActionCacheOperation, PolicyActionEntity) => {}
        },
      }
    }
  }
});
```



