---
layout: post
title: Deconstructing Apollo Part 3&#58; Reactive Variables
image: '/images/tech/reactive-variables.jpg'
category: Tech
tags: [JavaScript, Apollo, GraphQL, Cache, Reactive, Variables]
---

A reaction to Apollo 3's new state management solution.

<!--halt-->

# [Reactive variables](#reactive-variables)

As always, Apollo 3 provides its own great [documentation](https://www.apollographql.com/docs/react/local-state/reactive-variables/) on this topic, so I'd encourage anyone looking at this post to first start there. 

If you're still reading this, then I assume you're interested in learning even more about reactive variables and how they tie into the Apollo 3 ecosystem. In this example we'll explore how you can use them to extend an existing server type stored in your client cache with a client-side field.

## [Moving past local resolvers](#moving-past-local-resolvers)

Apollo has provided local state management solutions in the past and if you've worked with Apollo 2, you might be familiar with the now deprecated [local resolvers](https://www.apollographql.com/docs/react/local-state/local-state-management/#local-resolvers-deprecated). Local resolvers offered a way to store additional data in the client cache using a pattern that Apollo 3 developers were already familiar with.

In this example, we are extending the server `Employee` type to support a client-side `isDeleting` field that we update using a local resolver. This interface should look exactly like writing resolvers in the Apollo server-side schema.

```javascript
const isDeletingEmployee = gql`
  fragment isDeleting on Employee {
    __typename
    isDeleting @client
  }
`;

export default {
  typeDefs: gql`
    extend type Employee {
      """
      Whether the employee record is currently being deleted on the client
      """
      isDeleting: Boolean!
    }
  `,

  resolvers: {
    Mutation: {
      deleteEmployee: (
        _root,
        { employeeId },
        { cache, getCacheKey }
      ) => {
        const id = getCacheKey({
          __typename: 'Employee',
          id: employeeId,
        });
        const data = { isDeleting: true, __typename: 'Employee' };
        cache.writeFragment({
          fragment: isDeletingEmployee,
          id,
          data,
        });
      },
    },
    Employee: {
      isDeleting: (employee, _variables, { cache, getCacheKey }) => {
        const id = getCacheKey({
          __typename: 'Employee',
          id: employee.id,
        });
        /*
         * If the employee is not in the cache, then the readFragment call will
         * throw an exception
         */
        try {
          const queryResult = cache.readFragment({
            id,
            fragment: isDeletingEmployee,
          });
          return !!queryResult?.isDeleting;
        } catch {
          return false;
        }
      },
    },
  },
};
```

While this pattern is familiar, it can take a lot of code to extend a type with a single field like this. Let's compare this implementation to another using reactive variables.

## [Embracing reactive variables](#embracing-reactive-variables)

In their documentation, the Apollo team says the following:

> In Apollo Client 3, using cache policies and reactive variables, you can elegantly add pieces of local state to the cache. Apollo Client 2x used local resolvers to accomplish this, but we prefer the newer approach for its cleanliness and lack of verbosity.

Let's put that claim to the test!

To extend a server type, we'll need to combine reactive variables with Apollo 3's new type policies:

```javascript
import { makeVar } from '@apollo/client';

const currentlyDeletingEmployees = makeVar({});

export const cache: InMemoryCache = new InMemoryCache({
  typePolicies: {
    Employee: {
      fields: {
        isDeleting: {
          read (isDeletingValue, { readField }) {
            const employeeId = readField('id');
            return !!currentlyDeletingEmployees()[employeeId];
          },
        }
      }
    }
  }
});
```

We first create our `currentlyDeletingEmployees` reactive variable to keep track of which employees are being deleted on the client. We then write a new `isDeleting` field policy read function that defines how the `isDeleting` field is read for the `Employee` object.

The field policy includes a `readField` utility that let's us read properties of entities in the cache. If we provide no second argument of the entity to read from, it defaults to the current entity whose field is being accessed, in our case this is the employee. With the employee ID we are then able to check our reactive variable to see if it is being deleted.

> Note: When we query for our employee, we need to specify that the `isDeleting` field is a client-side field:

```javascript
export const GetEmployeeById = gql`
  query GetEmployeeBYId($employeeId: iD!) {
    employeeById(employeeId: $employeeId) { 
      id
      name
      isDeleting @client
    }
  }
`
```

## [Reacting to changes](#reacting-to-changes)

Any query that includes employees will now re-execute when the `isDeleting` value for their employee changes. This is the *reactive* part of reactive variables and it's what makes them so powerful and multi-purpose throughout your Apollo 3 applications.

To accomplish this, reactive variables hook into the same dependency and broadcasting mechanisms as the client cache.

The functonality that makes this possible is remarkably compact, so let's take a look at it as of [Apollo 3.2](https://github.com/apollographql/apollo-client/blob/master/src/cache/inmemory/reactiveVars.ts#L1):

```javascript
import { Slot } from "@wry/context";
import { dep } from "optimism";
import { InMemoryCache } from "./inMemoryCache";
import { ApolloCache } from '../../core';

export type ReactiveVar<T> = (newValue?: T) => T;

const varDep = dep<ReactiveVar<any>>();

// Contextual Slot that acquires its value when custom read functions are
// called in Policies#readField.
export const cacheSlot = new Slot<ApolloCache<any>>();

export function makeVar<T>(value: T): ReactiveVar<T> {
  const caches = new Set<ApolloCache<any>>();

  return function rv(newValue) {
    if (arguments.length > 0) {
      if (value !== newValue) {
        value = newValue!;
        varDep.dirty(rv);
        // Trigger broadcast for any caches that were previously involved
        // in reading this variable.
        caches.forEach(broadcast);
      }
    } else {
      // When reading from the variable, obtain the current cache from
      // context via cacheSlot. This isn't entirely foolproof, but it's
      // the same system that powers varDep.
      const cache = cacheSlot.getValue();
      if (cache) caches.add(cache);
      varDep(rv);
    }

    return value;
  };
}

type Broadcastable = ApolloCache<any> & {
  // This method is protected in InMemoryCache, which we are ignoring, but
  // we still want some semblance of type safety when we call it.
  broadcastWatches: InMemoryCache["broadcastWatches"];
};

function broadcast(cache: Broadcastable) {
  if (cache.broadcastWatches) {
    cache.broadcastWatches();
  }
}
```

The `makeVar` function keeps a list of caches to broadcast to when the value of the reactive variable changes. This is usually just the `InMemoryCache` containing the cached entities from Apollo Server.

As a client-side field is resolved, the cache records which field is being updated [here](https://github.com/apollographql/apollo-client/blob/master/src/core/LocalState.ts#L378:L378) and associates it with the current reactive variable by calling `varDep(rv)` to tie the current field to the reactive variable. The inner working of the [Optimism](https://github.com/benjamn/optimism) dependency library used by Apollo remain relatively abstruse and I will not and could not dive into how it works yet.

## [Using Reactive Variables in Components](#using-reactive-variables-in-components)

Reactive variables can be used in components with the `useReactiveVar` hook that came out in Apollo 3.2. Let's see how we can consume our `currentlyDeletingEmployees` reactive variable in a frontend experience:

```jsx
import { useReactiveVar } from '@apollo/client';

const EmployeeListItem = ({ id, name }) => {
  const isDeletingEmployee = useReactiveVar(currentlyDeletingEmployees)[id];
  return (
    <div>
      <h1>{name}</h1>
      <If condition={isDeleting}>
        <span>Deleting...</span>
      </If>
    </div>
  );
}
```

If we were to use the `currentlyDeletingEmployees` object directly in the React component without `useReactiveVar`, then it would not re-render if the value changed. Subscribing to changes to the reactive variable in the component using the `useReactiveVar` hook ensures that the component updates whenever the reactive variable does.

## [Working Together, Separately](#working-together-separately)

Apollo listened to the commmunity's desire for an easier way to achieve robust, reactive client state management without having to go through all of the hastle of local resolvers.

While reactive variables are not part of the client cache and their value are not stored within it, they are integrated with queries through field policies to provide automatic updates as needed.

* Are reactive variables the new shiny solution to client-side state management for applications using Apollo?
* Can users finally ditch local resolvers or other state management solutions like Redux?

In many cases, yes, and Apollo certainly hopes so. However, there are some limitations of how Reactive variables work that make them difficult to remedy with the rest of the client cache. Since they are not stored within the client cache, tools like [Apollo cache persist](https://www.google.com/search?q=apollo-cache-persist&oq=apollo-cache-persist&aqs=chrome..69i57j0l6j69i60.3489j0j1&sourceid=chrome&ie=UTF-8) will not work with reactive variables, and there is no current solution for persisting reactive variable state like there are for persisting entities in the client cache.

## [State of evolution](#state-of-evolution)

Reactive variables are a fundamentally new API in Apollo 3. While local resolvers were more verbose, they added minimal cognitive overhead for developers who had worked with writing Apollo GraphQL resolvers. Reactive variables are a clever state management solution, but they're very new and because they exist outside the cache, they feel somewhat shoehorned into the Apollo API as a solution to the community's desire for easier state management. 

I plan to use them more myself in the applications I work on and am interested to see how this new approach to state management evolves. From my limited experience with them so far, I would be keen to see reactive variables become first-class citizens of the cache itself in the future to further tie together the Apollo ecosystem.