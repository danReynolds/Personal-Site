---
layout: post
title: Redux to Apollo Part 2&#58; Mutation and Side Effects
image: '/images/tech/mutations-side-effects.jpg'
category: Tech
tags: [JavaScript, Apollo, GraphQL, Cache, Invalidation, Policies]
---

Moving past our first post where we talked about data access patterns, this second deep dive looks at handling data mutations
and side effects when moving from Redux to Apollo.

<!--halt-->

# Background

In part 1 of this series, we examined how we can use Apollo type policies to accomplish effective client-side data access like we had with our Redux selectors. Now that we have gone over patterns for accessing the data in our Apollo application, we can explore ways to manage data mutations and side effects.

## Mutating Data with Redux

Let's first take a look at how data mutations are handled in Redux applications. Redux is named after the `reduce` function, which takes as input the current element,
as well as the output of the previous iteration. The new output can then be a combination of the previous output and the the current element.

In plain JavaScript, a reduce function looks like this:

```typescript
const sum = [1, 2, 3].reduce((acc, elem) => acc + elem, 0);
console.log(sum); // 6
```

In Redux, the elements are called actions, the function run per action is called a reducer and the initial value is a global store object `{}`. A typical example of mutating the Redux store might then look something like this:

```typescript

// Reducer
function employees(state = { employees: [] }, action) {
  switch (action.type) {
    case 'GET_EMPLOYEES':
      return {
        ...state,
        employees: action.payload;
      };
    case 'UPDATE_EMPLOYEE':
      return {
        ...state,
        employees: {
          ...state.employees,
          employee[action.employeeId]: action.payload,
        }
      };
    case 'DELETE_EMPLOYEE':
      return {
        ...state,
        employees: employees.filter(employee => employee.id !== action.employeeId),
      };
    default:
      return state;
  }
}
```

When a `GET_EMPLOYEES` action is fired and comes back from the server, the reducer extracts its payload and mutates the state of the `employees` slice of the Redux store
to now include those employees. As we've talked about in the previous post on accessing data, these employees can then be read from the Redux store using selectors.

If an employee was then to be deleted using a `DELETE_EMPLOYEE` action, the reducer removes that employee from the list of employees.

As we can see, updating state with Redux is all manual and in the hands of the developer. One advantage to data mutation with Redux is that its very clear what is going on and there isn't much library magic doing things under the hood.

This also acts as a disadvantage though, as it means that the burden of handling all of these state updates is on the engineer, adding to the amount of effort and code to maintain wtih each additional data mutation.

## Mutating Data with Apollo

Now that we've seen how basic data mutation works with Redux, let's take a look at Apollo.

In this example, we're dealing with a data set of employees and teams at a company. The query that fetched the employees data looked like this:

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
      manager {
        id
        name
      }
      members {
        id
      }
    }
  }
}
```

and it is represented in the cache like this:

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

It can then be accessed in a basic React component as shown below:

```tsx
import React from 'react';
import { useQuery } from '@apollo/client';
import LoadingIndicator from './loadingIndicator';
import { GetEmployees } from './queries';

const EmployeeList = () => {
  const { data: employeesData, loading } = useQuery(
    GetEmployees,
    {
      fetchPolicy: 'cache-first',
    },
  );

  if (loading) {
    return <LoadingIndicator />;
  }

  const employees = employeesData?.employees?.data ?? [];

  const employeeListItems = employees.map((employee) => (
    <li
      key={employee.id}
    >
      {`Name: ${employee.name}`}
    </li>
  ));

  return <ul>{employeeListItems}</ul>;
}

const TeamsList = () => {
  const { data: teamsData, loading } = useQuery(
    GetEmployees,
    {
      fetchPolicy: 'cache-first',
    },
  );

  if (loading) {
    return <LoadingIndicator />;
  }

  const teams = teamsData?.teams?.data ?? [];

  const teamsListItems = teams.map((team) => (
    <li
      key={team.id}
    >
      {`Team name: ${team.name}\nManager: ${team.manager.name}`}
    </li>
  ));

  return <ul>{employeeListItems}</ul>;
}
```

This simple component fetches the list of employees using our query defined earlier, prioritizing reading the data from the cache if it already exists.

Given this setup, let's look at mutating our data.
## Updating the cache after a mutation

If an employee were to then leave the company, we'd want them to immediately stop showing up in our employees UI. The first tool we can turn to remove them from the cache is the Apollo 3 [evict API](https://www.apollographql.com/docs/react/caching/garbage-collection/#cacheevict).

When Charlie, the investment team manager at our company and employee number 3 in our cache, decides to leave, a mutation to delete him is executed on the client. In response to a successful mutation, it runs a custom update handler to evict the cached employee entity:

```typescript
import { gql } from '@apollo/client';

gql`
  mutation DeleteEmployee($employeeId: ID!) {
    deleteEmployee(employeeId: $employeeId) {
      success
    }
  }
`;

const deleteEmployee = (deleteEmployeeId: string) => {
  return useMutation(DELETE_EMPLOYEE, {
    variables: {
      employeeId: deleteEmployeeId,
    }
    update(cache) {
      cache.evict({
        id: `Employee:${deleteEmployeeId}`
      });
    }
  });
}
```

Charlie's normalized employee entity has now been removed from the cache and we can move on from the topic of cache eviction right? Well, not quite.

First we need to understand what happens to our cached `employees` and `teams` queries that contained references to the evicted employee. Apollo calls these references to normalized entities that are no longer in the cache *dangling references* and there are a couple of approaches to dealing with them.

## Leave-and-filter approach

The ideal outcome in terms of data consistency when this eviction call occurs would be for the cache to traverse its stored queries and remove the invalid references to the evicted entity. In reality, they remain in the cache, and Apollo makes note of this in their documentation:

> When an object is evicted from the cache, references to that object might remain in other cached objects. Apollo Client preserves these dangling references by default, because the referenced object might be written back to the cache at a later time. This means the reference might still be useful.

Because the references might become valid later, Apollo errs on the side of keeping them. This can cause problems though, since parts of our application could still be trying to read cached queries that contain these dangling references. To solve this problem, Apollo introduced a `canRead` utility accessible in your type policies to filter out dangling references:

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

This works, but having to define custom type policies for reading all the fields that could contain dangling references isn't very scalable, so instead, the cache will **automatically** do this for you for all **array** fields in the cache.

So where does that leave us? Are all our cache invalidation issues resolved? Again, not quite yet, we still have **two** important problems with this approach.

1. Since Charlie was an engineering manager, a reference to his employee entity existed not only in the array of team members, but also in the `manager` field which is not automatically filtered with `canRead` since it isn't an array field. We would still need to define our `manager` custom field policy as well as any others that reference evicted entities directly.

2. The second and more serious problem is that while this *leave them in and then filter them out* approach works great for the next time we try to read these cached queries, nothing has caused our existing subscriptions in the UI for query fields like `employees` or `teams` to re-execute and until they are re-run, they will still contain Charlie's employee reference!

So how can we tell our existing UIs to update after an entity is evicted? We'll need to explore an alternative method.

## Evict-on-write approach

Instead of leaving the dangling references in the cache, this time we'll explicitly remove the deleted employee reference. This will require us to additionally:

1. Evict the employee
2. Remove it from the cached `employees` query
3. Remove it from from `Team:2`'s `members` field that contained it
4. Remove it from `Team:2`'s manager field


Our update handler would then look like this:

```typescript
const deleteEmployee = (deleteEmployeeId: string) => {
  return useMutation(DELETE_EMPLOYEE, {
    variables: {
      employeeId: deletedEmployeeId,
    }
    update(cache) {
      // 1. Evict the employee
      cache.evict(`Employee:${deletedEmployeeId}`);

      // 2. Remove it from the cached `employees` query
      cache.modify({
        fields: {
          employees(employeesResponse, { canRead }) {
            const employees = employeesResponse?.data ?? [];
            const remainingEmployees = employees
              .filter(employeeRef => canRead(employeeRef));

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
          // 3. Remove the employee from the `Team:2` normalized entity that contains a reference to that employee
          members(teamMembers, { canRead }) {
            const remainingTeamMembers = employees
              .filter(teamMemberRef => canRead(teamMemberRef));

            return remainingTeamMembers;
          },
          // 4. Remove the `manager` field from any `Team` that had that employee as their manager
          manager(existingManager) {
            return null;
          }
        }
      });
    }
  });
}
```

The [modify API](https://www.apollographql.com/docs/react/caching/cache-interaction/#cachemodify) allows us to alter the value of any field in the cache, and we can use it to remove our deleted employee reference from both the cached `employees` query and the normalized `Team:2` entity under its `members` and `manager` fields. We then remove the deleted employee normalized entity same as we did before with the `evict` API.

Now any queries that had accessed the `employees` field or the `members` or `manager` of the `Team:2` entity will re-execute and our UI will correctly update to remove our deleted employee.

While we've solved some of our problems, this approach still has a couple shortcomings:

1. We're co-locating a lot of business logic with our `delete` mutation in our component. Ideally our component should just be able to call a delete mutation and not have to worry about removing entities from various places in our cache.

2. How did we know that `Team:2` was the correct team to remove Charlie's `Employee:3` entity from? We often won't have context like that when deleting entities, and we'd need to somehow iterate through all possible teams to see if any of them included it. 

To resolve these issues, we've created a cache invalidation companion library to ApolloClient at NerdWallet that helps to better codify relationships betweens entities in the cache.
## Apollo invalidation policies

The [Apollo invalidation policies](https://github.com/NerdWalletOSS/apollo-invalidation-policies) library is an extension of the Apollo 3 cache that provides a framework for managing the lifecycle and relationships of cache data through the concept of invalidation policies.

Like type policies, invalidation policies are declared for typenames of your GraphQL schema and form relationships between different types. The full API looks like this:

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

Let's demonstrate how we can use invalidation policies to accomplish the requirements of our `Evict-on-write` approach above.

Assuming our schema looks like this:

```typescript
type Employee {
  id: ID!
  name: String!
  role: String
  team: Team
}

type Team {
  id: ID!
  name: String!
  manager: Employee
  members: [Employee!]!
}

type EmployeesResponse {
  data: [Employee!]!
}

type DeleteEmployeeResponse {
  success: Boolean!
}

type Query {
  employees: EmployeesResponse
}

type Mutation {
  deleteEmployee(
    employeeId: ID!
  ): CreateEmployeeResponse
}
```

We can now form relationships between our schema types to handle cleanup of our deleted employee:

```typescript
const cache = new InvalidationPolicyCache({
  typePolicies: {...},
  invalidationPolicies: {
    types: {
      DeleteEmployeeResponse: {
        onWrite: {
          Employee: ({ evict, readField }, { id, ref, parent: { variables } }) => {
            if (readField('id', ref) === parent.variables.employeeId) {
              evict({ id });
            }
          },
        }
      },
      Employee: {
        onEvict: {
          EmployeesResponse: ({ readField, modify }, { storeFieldName, parent }) => {
            modify({
              fields: {
                [storeFieldName]: (employees, { canRead }) => {
                  return {
                    ...employees,
                    data: employees.data.filter(employeeRef => {
                      return canRead(employeeRef);
                    }),
                  };
                },
              },
            });
          },
          Team: ({ readField, modify }, { id, parent }) => {
            modify({
              id,
              fields: {
                members: (teamMembers, { canRead }) => {
                  return teamMembers.data.filter(teamMemberRef => {
                    return canRead(teamMemberRef);
                  });
                },
                manager: (managerRef, { canRead }) {
                  if (canRead(managerRef)) {
                    return managerRef;
                  }
                  return null;
                }
              }
            });
          },
        },
      },
    },
  },
});
```

The first type relationship we've established here is between the `DeleteEmployeeResponse` type and the `Employee` type.

On writing of a `DeleteEmployeeResponse` into the cache, it will iterate through all `Employee` entries in the cache and run our provided policy action function. When the function
encounters the employee with the ID of the one we just deleted, it evicts it from the cache.

The other type relationships we've written are between the `Employee` type and the `EmployeesResponse` and `Team` types. On eviction of our employee entity, it will iterate through all entries with an `EmployeesResponse` type and a `Team` type and filter out the removed employee.

We find that this approach has a handful of advantages for data mutations:

1. It centralizes the logic for invalidating the cache - developers can open up their invalidation policies and see what happens when changes are made to different types in the cache.
2. It codifies the relationships between types - The Apollo cache is not a relational database, it doesn't know that changes to one type might effect lifecycle of another. The problem is that many clients may be dealing with highly relationald data, and tools like invalidation policies can help by adding a relational layer on top of the core cache API.
3. It handles cases where you don't have the IDs of the entities that should be affected. In our example above, we didn't need to know that our deleted employee belonged to `Team:2`, the invalidation policy will go through all teams to look for that entity and remove them.

> Note: If iterating through all entities like this could be a performance concern because your application has a large number of entities of a given type and performs frequent updates, that's definitely something to consider and test.

Despite these benefits, it's still a good chunk of code and mental overhead for developers to process in order to achieve complete cache consistency and it illustrates the challenge of maintaining highly relational data on the client. Neither Redux nor Apollo Client were built expressly for managing highly relational data and if you have a solution you've found effective on your own projects I'd love to hear about it, you can find me on[Twitter](https://twitter.com/TheDerivative).

## Non-relational side effects

When managing state, it is often the case that there are side effects that need to be performed as a result of changes, such as firing analytics events or presenting users with notifications. These changes aren't codified by relationships between types, and require more flexibility so that we can support logic like *on deleting employee, fire an analytics event*.

In Redux, these sort of side effects can be achieved with [middleware](https://redux.js.org/understanding/history-and-design/middleware). Redux middlewares sit between actions and reducers and can perform arbitrary side effects when an action is fired.

Here's an example of using middleware to handle our requirement to fire an analytics event when an employee is deleted:

```typescript
import analytics from './analytics';
import { createStore, combineReducers, applyMiddleware } from 'redux';

const logger = store => next => action => {
  if (action.type === 'DELETE_EMPLOYEE') {
    analytics.track('DELETE_EMPLOYEE_EVENT', {
      id: action.variables.employeeId,
    });
  }
  next(action);
  return result
}

const rootReducer = combineReducers(reducers)
const store = createStore(
  rootReducer,
  applyMiddleware(analytics)
);
```

There's a bit of Redux boilerplate here so if you're not familiar with some of these APIs they're all covered in the Redux docs. Whenever an action is fired, it will first send it through the chain of middlewares, which are a set of composed functions that pass their output as the input to the next middleware in the chain. The last middleware sends its output to the reducers, which then process the action and update the application's state.

By adding our logging middleware, we can intercept actions and perform arbitrary side effects like our analytics tracking when an employee is deleted. Now that we've seen it with Redux, how can we accomplish it with Apollo?

## Apollo links

When GraphQL operations on the client are executed, Apollo sends them through a series of [links](https://www.apollographql.com/docs/react/api/link/introduction/), a chain of observable subscriptions that can modify the outbound operation and add additional behavior. The final terminating link then sends the operation out over the network. Sound familiar? Apollo's link mechanism for dispatching operations is somewhat similar to how Redux dispatches actions using middlewares.

Our Apollo analytics link would then look something like this:

```typescript
import analytics from './analytics';
import { ApolloLink } from '@apollo/client';

const analyticsLink = new ApolloLink((operation, forward) => {
  if (operation.operationName === 'DeleteEmployeeMutation') {
    analytics.track('DELETE_EMPLOYEE_EVENT', {
      id: operation.variables.employeeId,
    })
  }

  return forward(operation);
});
```

At first glance, this setup looks like the clear choice for replacing Redux middlewares when moving to Apollo, but it's important to call out some differences.

Redux middlewares process **actions**, which are used for updating the client's state in the global Redux store. Alternatively, Apollo links process **network-bound GraphQL operations**.

While middlewares manage side effects at the client's state management layer, Apollo links manage side effects at the client's network layer. This means that certain things you might be doing with Redux middlewares are not doable with an equivalent Apollo link.

GraphQL operations will not be processed by links if they use fetch policies that do not hit the network, like `cache-only`. If for example, a manager was editing some details about an employee and wanted to save their work locally as a draft using a schema and query like this:

```typescript
import { gql } from '@apollo/client';

type EmployeeDraftResponse {
  data: Employee!
}

extend type Mutation {
  saveEmployeeDraft(
    id: ID!
    name: String!
    role: String
    team: Team
  ) : EmployeeDraftResponse
}

client.writeQuery({
  query: gql`
    query saveDraft(
      $id: ID!
      $name: String!
      $role: String
      $team: Team!
    ) {
      saveEmployeeDraft(
        id: $id
        name: $name
        role: $role
        team: $team
      ) {
        data {
          id
          name
        }
      }
    }
  `,
  variables: {...},
  data: {...},
})
```

Since nothing is being sent over the network, an Apollo link would not be useful as a way to handle side effects for this operation.

## Invalidation policies

While Apollo links apply to the network layer, as cache extensions, invalidation policies apply to the state management layer similarly to Redux actions. Since they operate on types, an invalidation policy for handling a side effect when an employee draft is saved could look like this:


```typescript
import analytics from './analytics';
import { InvalidationPolicyCache } from 'apollo-invalidation-policies';

const cache = new InvalidationPolicyCache({
  typePolicies: {...},
  invalidationPolicies: {
    types: {
      EmployeeDraftResponse: {
        onWrite: {
          __default: (_cacheOperations, { parent: { variables }}) => {
            analytics.track('SAVE_EMPLOYEE_DRAFT', { id: variables.id });
          }
        },
      }
    }
  }
});
```

Instead of defining a type relationship between `EmployeeDraftResponse` and a second type, the write and evict policy events additionally support a `__default` field that will be executed whenever that event occurs for an entity of that type.

Invalidation policies have their own shortcomings here too, as they only work if your queries return response types as opposed to primitives, but we've made that a best practice of ours anyways. 

## Conclusion

That brings part 2 of this series on migrating from Redux to Apollo to a wrap! We've compared the way Redux and Apollo handle mutations and side effects and offered some different approaches to making the switch. While we've already been adopting these migration patterns at our own company, we are still learning what works best and look forward to sharing more updates on these topics in the future.

If you have any more topics on migrating from Redux to Apollo that you'd like to discuss or have followups for what we've talked about here, don't hesitate to reach out on [Twitter](https://twitter.com/TheDerivative) and if you'd like to explore more features of [Apollo invalidation policies](https://github.com/NerdWalletOSS/apollo-invalidation-policies), feel free to check it out. I plan to write more on some additional APIs like type-based TTLs that it currently supports in the future.

That's it for now!


