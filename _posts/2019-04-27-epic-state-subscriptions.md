---
layout: post
title: Epic State Subscriptions
image: '/images/tech/actions.jpg'
category: Tech
tags: [Redux, RxJS, Epics]
---

A state subscriptions library for transforming a stream of Redux actions into a stream of path changes.

<!--halt-->

# What is a State Subscription?

The purpose of a state subscription is to detect when a change occurs to a path
we care about in the Redux store and perform any necessary side effects.

Redux already provides us with a tool for detecting basic changes to the Redux store using [middlewares](https://redux.js.org/advanced/middleware).

Redux middlewares run in-between the dispatching of an action and the receiving of the actions by the reducers. 

A basic state subscription middleware could look something like this:

```javascript
const middleware = store => {
    const { dispatch, getState } = store;

    return next => action => {
        const prevState = getState();
        const result = next(action);
        const nextState = getState();

        if (nextState.path !== prevState.path) {
            // Perform side effect
            dispatch(sideEffectAction());
        }
        return result;
    };
}
```

Under the hood, middlewares are functions that get composed together in the order that they are applied when the store is created.

Consider middleware functions applied in the order `a, b`. This middleware chain is composed as `a(b(store.dispatch)))` so that the `next` in each middleware references
the next middleware function to hand the action off to, all the way until it reaches the redux `dispatch` method which runs it through the reducers.

In the above example, we grab the current state, let the action run through the middleware chain and the reducers by handing off to `next` and then re-fetch the current state. By comparing the previous state
to the next state we're able to see if the paths we care about have been mutated in the Redux store and huzzah!

We've made a basic state subscription.

# Making Subscriptions Generic

We have a number of use cases for monitoring changes to the Redux store in our applications and we want to apply our state subscription solution generically to all of them.

One example is our React Native application's persistent storage. We have a need to persist specific parts of our Redux store across user sessions in order to deliver a great user experience on returning to the app. We can achieve this by monitoring for changes to our Redux state and sending them down to the native layer where they can be stored securely across app launches.

The core requirements for this functionality would be that it is:

1. **Asynchronous** - Persisting changes to native storage takes time, Redux middlewares should not be blocked while performing the side effects of our state subscriptions
2. **Ordered** - Changes to the state should be queued and persisted in the order that they were detected
3. **Performant** - The Redux store changes frequently, since all we care about at time `x` is the current state of the Redux store, we can batch actions together

Asynchronous side effects? Ordered buffers? This sounds like a perfect application of Redux-Observable!

If you are unfamiliar with Redux-Observable, it is a reactive programming library that applies the observable pattern using RxJS to create observable streams of actions. To learn more about it and observables in general you can check out a [previous post]({% post_url 2018-01-18-Using-RxJS %}).

# Epic State Subscriptions

The core primitive of Redux-Observable are epics, functions which receive a stream of actions and returns a stream of actions. **Actions in**. **Actions out**.

![Redux Observable Process Diagram](/images/tech/redux-observable-process-diagram.png)

All the state subscription needs to do is transform a stream of actions into a stream of path changes and then standard RxJS operators can do the rest. This functionality is available as its own RxJS operator supplied by our [Epic State Subscriptions](https://github.com/NerdWalletOSS/epic-state-subscriptions) library.

```javascript
import { ignoreElements, tap } from 'rxjs/operators';
import { createStateSubscription } from 'epic-state-subscriptions';
import { sideEffectAction } from './Actions';

const persistenceEpic = (action$, state$) =>
  action$.pipe(
    createStateSubscription(state$, {
      paths: ['x.y.z', 'a.b.*', '*.c.d'],
    }),
    tap(paths => {
      paths.forEach({ path, nextState } => {
        NativeLayer.persist(path, nextState);
      });
      return sideEffectAction();
    }),
  );
```

The persistence epic receives the mapped actions as a stream of path changes that we can then persist to the native layer. Epics satisfy our **asynchronous** requirement, as they run separately, after middlewares and reducers have processed the action. 

Each set of path changes emitted by the state subscription observable is mapped to a call to the native persistence module using the RxJS side effect `tap` operator.

Our second requirement is to make sure that our state subscriptions are persisted **in order**. We can accomplish this ordering by changing `tap` to a `concatMap` and returning our path changes as an inner observable:

```javascript
import { concatMap } from 'rxjs/operators';
import { from } from 'rxjs';
import { createStateSubscription } from 'epic-state-subscriptions';

const persistenceEpic = (action$, state$) =>
  action$.pipe(
    createStateSubscription(state$, {
      paths: ['x.y.z', 'a.b.*', '*.c.d'],
    }),
    concatMap(paths => {
      return from(paths.map({ path, nextState } => {
        NativeLayer.persist(path, nextState);
      }));
    })
  );
```

Let's work our way up to the definition of the `concatMap` operator:

* The `map` operator projects each value emitted from the source observable to a new value.
* The `mergeMap` operator maps each value emitted by the source observable to an inner observable.
* The `concatMap` operator is similar to `mergeMap`, but it only subscribes to the next inner observable when the previous one completes.

In our example, `concatMap` maps each set of path changes emitted by the source observable to an inner observable of promises using the `from` operator. Once the promises all succeed, the inner observable completes
and `concatMap` processes the next value emitted by the source observable.

In this way, we guarantee that the state subscription changes are processed in order and have prevented a slower call to the native layer from clobbering a later call.

All that is left is to make our state subscription epic more **performant**. We can use the `bufferTime` operator to throttle the frequency with which we calculate state subscriptions:

```javascript
import { bufferTime, concatMap, filter } from 'rxjs/operators';
import { from } from 'rxjs';
import { createStateSubscription } from 'epic-state-subscriptions';

const SUBSCRIPTION_BUFFER_INTERVAL = 100;

const persistenceEpic = (action$, state$) =>
  action$.pipe(
    bufferTime(SUBSCRIPTION_BUFFER_INTERVAL),
    filter(actions => actions.length > 0),
    createStateSubscription(state$, {
      paths: ['x.y.z', 'a.b.*', '*.c.d'],
    }),
    concatMap(paths => {
      return from(paths.map({ path, nextState } => {
        NativeLayer.persist(path, nextState);
      }));
    })
  );
```

The `bufferTime` operator receives values from the action stream source observable and buffers them together, emitting all of them as an array of values on a fixed interval. Since it emits on that interval regardless of whether values have been received, a `filter` is used to make sure that actions occurred within the interval.

The state subscription operator is then notified of the potential change to the Redux store and calculates any path changes to emit.

# Subscribe!

We've now built a generic solution for subscribing to path changes we care about in the Redux store.

RxJS gives us the power to easily build on top of these path changes, incorporating complex operations like sequencing and buffering with only a few extra operators.

You can [check out the library here](https://github.com/NerdWalletOSS/epic-state-subscriptions) to see the full API and examples. That's all for now!







