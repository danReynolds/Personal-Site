---
layout: post
title: Managing Side Effects in Apollo with Streams
image: '/images/tech/apollo-streams.jpg'
category: Tech
tags: [Apollo, GraphQL, Streams, RxJS]
---

Using streams to manage side effects in the Apollo cache.

<!--halt-->

## Thinking in Streams

When we typically talk about fetching data, we usually think about calling a function that makes a network request to a server, or a query to a local cache that returns a value back to us asynchronously. Streams take this pattern a step further by allowing us to receive not just a single value, but multiple values over time.

Our code can subscribe to a particular stream and then asynchronously receive data whenever the stream emits new data. You can visualize this streaming concept as a pipe, where on one end, a data source can put data into the pipe, and on the other end subscribers receive that data.

## Apollo is Built on Streams

If you've worked with the Apollo library before, you're most likely familiar with some of its APIs for accessing data like `useQuery` hook. This React hook takes a given query and subscribes to the Apollo cache so that the component updates whenever that data our query cares about changes.

In the example below, our component is subscribing to changes in the Apollo cache for the `employees` field:

```javascript
import React from 'react';
import { useQuery, gql } from '@apollo/client';

const Component = () => {
  const { data } = useQuery(
    gql`
      query GetEmployees {
        employees {
          id
          name
          team
        }
      }
    `,
  )
}
```

Apollo uses streams under the hood to manage informing clients of changes to the `employees` field. When the `employees` field changes, our `useQuery` subscription is piped a new value from the cache and our component re-renders.

## Building Data Streams with Type Policies

So far we've seen how to query the server for data, but what about querying for data derived from the cache? What if we only wanted to be read data from the cache for employees of a particular team?

Apollo makes this possible with [Type Policies](https://www.apollographql.com/docs/react/caching/cache-field-behavior/). Type policies allow us to create derived data fields that act as views into the cache data. If we wanted to keep track of all the banking team employees, we could create a type policy like the following:

```javascript
import { InMemoryCache } from '@apollo/client';

const cache = InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        bankingEmployees: {
          read(_existingEmployees, { readField }) {
            const employeeReferences = readField('employees') ?? [];
            return employeeReferences.filter(employeeRef => readField('team', employeeRef) === 'Banking');
          }
        }
      }
    }
  }
})
```

Our type policy is built on top of the `employees` field we queried for earlier and filters down the list of employees to ones from the team we care about. We can then set up a new query that is subscribed to our `bankingEmployees` field:

```javascript
import React from 'react';
import { useQuery, gql } from '@apollo/client';

const Component = () => {
  const { data } = useQuery(
    gql`
      query GetBankingEmployees {
        bankingEmployees @client {
          id
          name
          team
        }
      }
    `,
  )
}
```

Now our components can retrieve a list of banking employees from the cache and because type policy fields are memoized like any other field, they won't re-render or get piped new data unnecessarily until a change is made to invalidate them.

## Building Side Effect Streams with watchQuery

Type policies are a great tool for subscribing to data we care about in the cache. But what if what we want to know is just the *fact that something changed*, not any particular data? Our type policy for the `bankingEmployees` field is is a data stream. Whenever the banking employees change, it emits the updated array of them to us. An event stream could be something more like:

> when a new banking employee is added, fire an analytics event

Our first thought could be to create a type policy that picks up changes to the banking employees field just like we did before. Let's see what that would look like:

```javascript
import _ from 'lodash';
import { InMemoryCache } from '@apollo/client';

const cache = InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        onBankingEmployeesChanged: {
          read(existingBankingEmployees, { readField }) {
            const newBankingEmployees = readField('bankingEmployees');
            const haveBankingEmployeesChanged = _.xorBy(
              newBankingEmployees,
              existingBankingEmployees,
              (ref) => ref.__ref
            ).length > 0;

            if (haveBankingEmployeesChanged) {
              fireAnalyticsEvent();
            }
          }
        }
      }
    }
  }
});
```

In order for this type policy to fire, some query will need to subscribe to this field since Apollo won't re-compute fields that aren't actively being listened to. The part that is a little strange is just the fact that our event for when a banking employee changes is now its own field in the cache that can be queried for. This field has no return value like other fields do and it's not used for its data, it is just a mechanism for triggering side effects.

It would be nice to have a way to subscribe to changes in the cache for the purpose of executing side effects and without having to add new fields. We can create this ourselves by taking advantage of how Apollo is built on streams.

The `useQuery` hook we looked at earlier allows components to subscribe to changes to the fields they care about in the Apollo cache. Under the hood, `useQuery` indirectly triggers the `ApolloClient.watchQuery` API to create this observable stream of changes for the given query.

```typescript
public watchQuery<T = any, TVariables = OperationVariables>(
  options: WatchQueryOptions<TVariables, T>,
): ObservableQuery<T, TVariables> => {...}
```

As we can in the `watchQuery` function signature, it will be returning an observable query object. `ObservableQuery` extends the `Observable` API from the [Zen Observable library](https://github.com/zenparsing/zen-observable), which is Apollo's chosen library for streaming data.

The observable returned from `watchQuery` can then be subscribed to in order to receive a stream of changes. By working directly with the `watchQuery` API, we can built streams for handling side effects without introducing new fields and type policies.

Our first step is to convert the `Zen Observable` we get from `watchData` to an RxJS observable. While everything we're about to do is possible with `Zen Observable`, it's a relatively small library with only a handful of stream utilities built-in. By using RxJS, we'll be able to handle a broader set of streaming use cases without needing to roll our own toolbox of utilities and helpers. You can read more about [RxJS here](https://rxjs.dev/guide/overview). We can convert the `watchQuery` response to use RxJS as shown below:

```typescript
import {
  WatchQueryOptions,
  Observable as ZenObservable,
} from '@apollo/client';
import { Observable as RxObservable, Subject, Subscription } from 'rxjs';

const zenToRx = <T>(zenObservable: ZenObservable<T>): Subject<T> => {
  const observable = new RxObservable<T>(observer =>
    zenObservable.subscribe(observer)
  );

  const subject = new Subject<T>();
  observable.subscribe(subject);

  return subject;
};

export const streamQuery = <TVariables, TData>(
  options: WatchQueryOptions<TVariables, TData>
) => {
  return zenToRx(ZenObservable.from(apolloClient.watchQuery(options)));
};
```

We can then re-create our banking employees analytics side effect using a streamed query:

```typescript
import { gql } from '@nerdwallet/apollo';
import { map, pairwise, startWith, tap } from 'rxjs/operators';
import { streamQuery } from './streams';

const bankingEmployeesQuery = gql`
  query GetBankingEmployees {
    readBankingEmployees @client {
      id
    }
  }
`;

export const bankingEmployeesChangedStream: Observable<void> = streamQuery({
  query: bankingEmployeesQuery,
}).pipe(
  map(result => result?.data?.readBankingEmployees),
  startWith([]),
  pairwise(),
  filter(([existingBankingEmployees, nextBankingEmployees]) => {
    return _.xorBy(
      newBankingEmployees,
      existingBankingEmployees,
      (ref) => ref.__ref
    ).length > 0;
  }),
);
```

If you have used RxJS before, the stream operators we use here are likely pretty familiar, but for the rest of us let's break down what's going on in this new cache subscription.

We first call `streamQuery` with the query we will subscribe to in the Apollo cache to get the banking employees. We then call the RxJS observable `pipe` function that allows us to use a set of `pipeable operators` like `map`, `startWith`, `pairwise` and `filter` to transform our stream.

Let's go through the chain of operators one by one:

1. [map](https://rxjs.dev/api/operators/map): First we use the `map` operator to transform our query response to extract the `bankingEmployees` field we care about.
2. [startWith](https://rxjs.dev/api/operators/startWith): We then tell the stream to start with an empty array using the `startWith` operator.
3. [pairwise](https://rxjs.dev/api/operators/pairwise): Next, the `pairwise` operator transforms our stream to deliver an array of the previous value and the current value from the input stream instead of just the current value. This allows us to compare the current and new value like we were able to with type policies.
4. [filter](https://rxjs.dev/api/operators/filter): The `filter` is analogous to `Array.filter` and transforms the stream to omit events that don't pass the filter's test. We use `filter` to only emit events when the banking employees have changed.

Our new `bankingEmployeesChangedStream` can now be subscribed to anywhere in our code to start watching for changes as shown below:

```typescript
import { bankingEmployeesChangedStream } from './banking';

const subscription = bankingEmployeesChangedStream.subscribe(() => {
  fireAnalyticsEvent();
});

// Later
subscription.unsubscribe();
```

> Note: When we `subscribe` to the stream, it returns a stream subscription that we can then unsubscribe from later on if we want to stop listening to changes.

## Creating a useStream Hook

What about using our side-effect stream in React components? We can easily accomplish this with a stream hook:

```typescript
export function useStream<TData = any>(
  stream: Observable<TData>,
  callback: (data: TData) => any
): Subscription {
  const streamSubscriptionRef = useRef<Subscription>();

  useUnmount(() => {
    const streamSubscription = streamSubscriptionRef.current;
    if (streamSubscription && !streamSubscription.closed) {
      streamSubscription.unsubscribe();
    }
  });

  if (!streamSubscriptionRef.current) {
    streamSubscriptionRef.current = stream.subscribe(data => {
      callback(data);
    });
  }

  return streamSubscriptionRef.current;
}
```

Now our React components can handle side effects with `useStream` similarly to how they accessed data with `useQuery`. Using our banking employees side effect stream in a component can then look like this:

```typescript
import React from 'react';
import { useStream } from '../streams';

const Component = () => {
  useStream(
    bankingEmployeesChangedStream,
    () => {
      fireAnalyticsEvent();
    }
  )
};
```

## That's it!

That's all we have for now on handling side effects in the Apollo cache with streams. Hopefully we've clarified how Apollo and tools like `useQuery` work under the hood to deliver data updates and shown that with some tweaking, we can use the same APIs to effectively hook into side effects. 







