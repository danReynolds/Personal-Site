---
layout: post
title: Using Redux Observable to Retry Requests
image: '/images/tech/jest.png'.png'
category: Tech
tags: [Redux, RxJS]
---

RxJS is well suited for handling retrying of requests and the Redux Observable middleware
allows us to integrate it into our React-Redux application.

<!--halt-->

# What is it?

Redux Observable is a library built around RxJS, a reactive programming library that allows you to
effectively manage sequences of asynchronous events using observables.

You can think of RxJS as Lodash for promises and Redux-Observable as Lodash for asynchronous redux actions.

# RxJS

To understand Redux-Observable, first you need to know RxJS.

RxJS uses Observables, Observers and Subscriptions to handle processing of events.

If you want to learn more about RxJS after this really brief summary, checkout their [official docs](http://reactivex.io/rxjs/manual/overview.html#introduction),
they're really good and most of the good content here is coming from them.

# Observables

I found these charts from RxJS really helpful in understand Observables and their place
among other producers/consumers:

![pushPull](/images/tech/push-pull.png)
![pushPull](/images/tech/push-pull-definitions.png)

We are generally more familiar with pulling values synchronously with functions and iterators.

When we want to have a single value pushed to us, we use promises. Observables sort of look like promises for multiple values,
but the way that RxJS recommends you think about them is as functions that can be either synchronous or asynchronous and return 0 to many values.

# Synchronous and Single Value

To use an observable you need to subscribe to it, which is analogous to calling a function:

```javascript
const foo = Rx.Observable.create(function (observer) {
  console.log('Hello');
  observer.next(42);
});

foo.subscribe(function (x) {
  console.log(x);
});
foo.subscribe(function (y) {
  console.log(y);
});
// Output:
// "Hello"
// 42
// "Hello"
// 42
```

We create an **observable** which emits a value of 42 to its **observer**, similarly to a generator. We **subscribe** to the **observable**
in order to start its **observable execution** and it **synchronously** emits a value of 42.

# Asynchronous and Multiple Values

```javascript
const observable = Rx.Observable.create(function subscribe(observer) {
  setInterval(() => {
    observer.next('Hello');
  }, 1000);
});
const subscription = observable.subscribe((x) => console.log(x));
setTimeout(() => subscription.unsubscribe(), 2000);
);
```

Now if we subscribe to the **observer**, it will emit a value of `Hello` **asynchronously** every second. This **observable execution** could run forever,
so to stop it, each call to subscribe returns a **subscription** object that we can then **unsubscribe** to, releasing the resources of the execution.

# Unicast Observables

A normal Observable is unicast. Unlike an event emitter, each subscription has its own observable execution.

```javascript
const observable = Rx.Observable.create(function subscribe(observer) {
  const interval = Math.random() * 1000;
  setInterval(() => {
    observer.next(interval);
  }, interval);
});
var subject = new Rx.Subject();
const subscription = observable.subscribe((x) => console.log(x));
const subscription2 = observable.subscribe((x) => console.log(x));
setTimeout(() => { subscription.unsubscribe(); subscription2.unsubscribe() }, 2000);
// Output:
// "726.3712515255427"
// "834.8198863348033"
// "726.3712515255427"
// "834.8198863348033"
```

Each subscription had its own observable execution, generating different random intervals.

# Multicast Observables

A Subject is a both an observable and an observer. It is multicast, sharing one observable execution and behaves like an event emitter.

```javascript
const observable = Rx.Observable.create(function subscribe(observer) {
  const interval = Math.random() * 1000;
  setInterval(() => {
    observer.next(interval);
  }, interval);
});
var subject = new Rx.Subject();
const subscription = subject.subscribe((x) => console.log(x));
const subscription2 = subject.subscribe((x) => console.log(x));
observable.subscribe(subject);
setTimeout(() => subject.unsubscribe(), 2000);
// Output:
// "976.9587382573253"
// "976.9587382573253"
// "976.9587382573253"
// "976.9587382573253"
```

Here we have 2 subscriptions subscribe to the subject like any other observable. We then pass the subject in to
an observable as an observer. Both subscriptions share the same observable execution and the observer multicasts events to both.

# Using RxJS with Redux Actions

Now that we are RxJS masters, let's add it to our Redux app!

Redux-Observable allows us to operate on streams of actions, similarly to how RxJS operates on streams of events.

You create epics, functions which take a stream of actions and returns an optionally transformed stream of actions.

You configure it by hooking up its `epicMiddleware` like any other middleware:

```javascript
import { createEpicMiddleware } from 'redux-observable';
import rootEpic from './epics';

const epicMiddleware = createEpicMiddleware(rootEpic);
const middlewares = [
  epicMiddleware,
  ...
];
```

# Epics

Here is a simple epic example straight from their docs:

```javascript
const pingEpic = action$ =>
  action$.filter(action => action.type === 'PING')
    .mapTo({ type: 'PONG' });

// later...
dispatch({ type: 'PING' });
```

Our epic takes in a stream of actions and filters them to a certain type. It then maps it to an action of type `PONG` and fires that action, essentially eqiivalent to:

```javascript
dispatch({ type: 'PING' });
dispatch({ type: 'PONG' });
```

# Retrying Requests

In our React-Native Redux app, a spotty connection could result in some of our requests failing and we wanted to make these requests retriable.

We are using this amazing open source async actions library called [Redux Easy Async](https://github.com/evanhobbs/redux-easy-async) that generates
start, success and fail actions for async requests.

using redux-easy-async and redux-observable we built a retry epic.

# Retry Epic

```javascript
const retryEpic = action$ =>
  action$.do(action => retrySubject.next(action))
  .filter(isRetriable).mergeMap((action) => {
    const failures = action.meta.failures || 0;
    const retryAction = retriableAction(action, { failures: failures + 1 });
    const retryActionObservable = Observable.of(retryAction);

    // If online, schedule the action for re-trying after waiting an exponential delay.
    if (global.navigator.onLine) {
      return retryActionObservable.delay(calculateExponentialBackoff(failures));
    }

    // If not online, schedule the action for re-trying when network connectivity changes.
    return Observable.fromEvent(NetInfo, 'connectionChange')
      .first().mergeMap(() => retryActionObservable);
  });
```

Here we take advantage of a number of RxJS utility methods. This is where it starts looking like Lodash. RxJS has great docs
for all of the supported utility methods. Check them out [here](http://reactivex.io/rxjs/class/es6/Observable.js~Observable.html).

# retriableDispatch

Anywhere we want to dispatch a retriable action, call `retriableDispatch(dispatch, action()` instead. For example, we do
`retriableDispatch(dispatch, requestFeatureFlags(true)` when the app starts up to retry important calls like to get feature flags.

```javascript
export const retriableDispatch = (dispatch, action, args = {}) => {
  const retryAction = retriableAction(action, args);
  const failType = retryAction.failActionCreator().type;
  const successType = retryAction.successActionCreator().type;
  const { meta: { retries, retryId } } = retryAction;

  return new Promise((resolve, reject) => {
    const cancelObservable = retrySubject.first(
      act => act.type === failType && act.meta.retryId === retryId && !act.meta.shouldRetry(act)
    );
    const failureObservable = retrySubject
      .filter(({ type, meta }) => type === failType && meta.retryId === retryId).take(retries + 1)
      .last();
    const successObservable = retrySubject
      .first(({ type, meta }) => type === successType && meta.retryId === retryId);

    Observable.race(
      cancelObservable,
      failureObservable,
      successObservable
    ).subscribe(({ type, payload }) => (type === successType ? resolve(payload) : reject(payload)));

    dispatch(retryAction);
  });
};
```

# How it works

We first convert the action to a retriable action, which just adds meta data to the action like how many times it has failed, and an unique identifier.

We then return a promise, so that callers can chain the async dispatch:

```javascript
retriableDispatch(dispatch, requestFeatureFlags()).then(dispatch(otherAction()));
```

The promise resolves or rejects based on the actions sent to the retrySubject. We subscribe to `Observable.race`, an observable that mirrors the first observable to emit.

The race is between a success action, a certain number of failures, or a cancel, which can happen if a retriable action's `shouldRetry` boolean function returns false based on changes in
the application's state.

# Where Else can we Use It?

I think redux-observable and RxJS in general is great for situations like retrying where you want to observe and act on streams of actions. Think about filtering and doing things in response to certain actions, or combinations of actions.


If you take a look at this post on [6 RxJS operators to know](https://netbasal.com/rxjs-six-operators-that-you-must-know-5ed3b6e238a0) you can see possible applications like waiting for a certain sequence of actions before doing something.

# You are already using it!

Redux uses reducers that react to actions, take in state, produce new state and pass it down to components. This can be accomplished with a single line of RxJS:

```javascript
action$.scan(reducer).subscribe(renderer)  
```

Here, a scan is performed on a stream of actions, which is like the javascript reduce method, except that it emits the current accumulated value with each iteration.

```javascript
[1, 2, 3].scan((acc, i) => {
  return acc + i;
}, 0);
// Output:
// 1
// 3
// 6
```

Each time it emits, the react component receives the new state and can re-render.

# Try it out!

RxJS can be used in combination with Redux-Observable or without, give it a try!
