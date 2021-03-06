---
layout: post
title: Moving from Ava to Jest
image: '/images/tech/jest.png'
category: Tech
tags: [project, jest, testing, ava]
---

We recently moved from Ava to Jest for our testing framework and we saw both speedups
and welcome new features.

<!--halt-->

# What do we Gain?

Benefits:

- Locally it has sped up our tests tests from about 40-50 seconds for Ava, to 8-10 for jest
- On Travis it has cut test runs down about 9-10 minutes
- My system doesn't freeze up from Ava memory spiking and making my fans run like crazy :)
- Allows for nested tests
- Includes own mocking library based on Jasmine
- Allows for interactive test debugging
- Snapshot testing
- Allows us to remove multiple dependencies such as mockery, react-native-mock, ava
- Made by Facebook and has a strong React/React-native community + better docs

Negatives:

You need to know a couple different ways to mock things and when to use each, hopefully this can address that though.

# New Testing Scripts

The Ava test scripts in the `package.json` have been replaced with the following:

```js
// basic testing
"test": "jest",
// debugging tests
"test:debug": "node --inspect-brk node_modules/.bin/jest --runInBand",
// do not show anything output to console, hides warnings
"test:silent": "jest --silent",
// enter Jest's interactive test watching
"test:watch": "jest --watch",
// only run tests related to files staged files
"test:change": "jest --onlyChanged",
// stop running the tests once an error is encountered
"test:failfast": "jest --bail",
// Run the tests and output coverage using at most 4 workers since travis has limited
// concurrency
"coverage": "npm run test:silent -- --coverage --maxWorkers=4",
// Jest will output coverage data to `lcov.info`, send that to coveralls
"coveralls": "npm run coverage && cat ./coverage/lcov.info | coveralls",
```

All the commands support sending a path as an argument for running specific tests. My preference
is for doing `npm run test:silent` because it makes seeing the tests that passed easier,
we could consider using it as the default going forward.

# Debugging Tests

What the heck is `node --inspect-brk node_modules/.bin/jest --runInBand`?

You can visit the node docs [here](https://nodejs.org/en/docs/inspector/).

`inspect-brk` basically enables the inspctor and then we run jest with the `runInBand` flag,
which makes tests run synchronously since the debugging doesn't work well with multiple processes.

It is described in more detail [here](http://facebook.github.io/jest/docs/en/troubleshooting.html).

Steps to debugging:

1. To use it drop a debugger in the file you want to go to
2. Run `npm test:debug` optionally with a path to the specific file
3. Open `chrome://inspect` and click the node session listed there
4. Now with this tab open it will take you to the inspector every time you run `test:debug`
5. Debug like normally!

Note that this requires node > 8 so to get this feature and general performance improvements bump to
node `v8.7.0` from https://nodejs.org/en/

# How to Test with Jest

Jest has [good documentation](http://facebook.github.io/jest/docs/en/api.html). The core mocking features are:

* `jest.fn`
* `jest.spyOn`
* `jest.mock`
* `jest.mockClear`
* `jest.mockRestore`
* `jest.doMock`
* `jest.resetModules`

as well as lifecycle hooks like `beforeEach`, `afterEach`, `beforeAll`, `afterAll` and test groupings
using `describe`.

# Using jest.mock

`jest.mock` is used to mock out the implementation of a module.

It takes a second argument that is the replacement implementation, which is what we're now using in our `Test/Setup.js` like we were with mockery to replace implementations:

```javascript
jest.mock('@nerdwallet/nwa', () => ({
  NWA: () => ({
    track: (eventName, eventProps, callback) => {
      if (callback) process.nextTick(callback);
    },
    trackPageView: () => jest.fn(),
    generatePageViewId: () => jest.fn(),
    setGlobalProp: () => jest.fn(),
    enableLogger: () => jest.fn(),
    getGlobalProps: () => jest.fn(),
    getUserProps: () => jest.fn(),
  }),
}));
```

# Using jest.fn

`jest.fn` returns a mock function that is used in the `Tests/Setup.js` a lot as the mock out
the implementation of modules. You can pass it a return value like shown here:


```javascript
const mockFn = jest.fn();
mockFn();
expect(mockFn).toHaveBeenCalled();

// With a mock implementation:
const returnsTrue = jest.fn(() => true);
console.log(returnsTrue()); // true;
```

I don't use it much outside of the test setup file though because it doesn't provide a way to restore
the original implementation of functions, so you'd need to keep a reference to the original.

# Using jest.spyOn

`jest.spyOn` is what I recommend using most, it creates a mock function similar to `jest.fn` but also
tracks calls to the function and supports `mockClear` and `mockRestore` for reseting calls to the mock and restoring the original implementation of what you mocked.

In the `test-apptentive` file I used it before all tests to mock out `NWApptentive`:

```javascript
jest.spyOn(NWApptentive, 'engage').mockReturnValue(Promise.resolve(true));
jest.spyOn(NWApptentive, 'setUserInfo').mockReturnValue(Promise.resolve(true));
jest.spyOn(Utilities, 'logError');
```

First specify the module, then the method to mock off of it as a string and use mock methods like `mockReturnValue` or `mockImplementation` or any others from [here](http://facebook.github.io/jest/docs/en/mock-function-api.html#mockfnmockreturnvaluevalue).

# Example Test

```javascript
test('apptentive middleware should clear user\'s info on signout', () => {
  const action = signout.success();
  store.dispatch(action);
  expect(NWApptentive.setUserInfo).toHaveBeenCalledWith(null, null);
});
```

```javascript
afterEach(() => {
  NWApptentive.engage.mockClear();
  NWApptentive.setUserInfo.mockClear();
  Utilities.logError.mockClear();
});
```

In between tests here I use `mockClear` to reset calls to them or sometimes `mockRestore` if you need the original functionality in a different test in that file. You don't need to restore it if you're done with it for the file.

# jest.doMock

> When using babel-jest, calls to mock will automatically be hoisted to the top of the code block. Use this method if you want to explicitly avoid this behavior.

There are only a couple cases in our code where we need different module implementations *between* tests in the same file and if you do then use `doMock` which is similar to mock but does not get hoisted and interfere with other tests.

One example is the `Platform` module:

# Another Example

```javascript
describe('Android < 5.0', () => {
  beforeAll(() => {
    const mockVersion = AndroidSdkVersions['5.0'] - 1;
    jest.doMock('Platform', () => ({ OS: 'android', Version: mockVersion }));
  });

  afterAll(() => {
    jest.resetModules();
  });

  test('Should return false if access token not present', () => {
    state.auth.hasAccessToken = false;
    expect(isAuthSessionReady(state)).toBe(false);
  });

  test('Should return true if access token present', () => {
    expect(isAuthSessionReady(state)).toBe(true);
  });
});
```

Here I want to set the Platform just for the Android section in the test file. I can use
the lifecycle hooks of beforeAll and afterAll for this test group.

# jest.resetModules

After the test group we **need** to do call `jest.resetModules` to clear the module registry cache and restore the implementation so that iOS can similarly use `doMock`.

Do not just try to do another `doMock` on top of the old one.

# Example of Accessing Spies

Here we setup some event listeners in the middleware that we want to call in our tests.

```javascript
beforeAll(() => {
  addEventListenerSpy = jest.spyOn(PushNotificationIOS, 'addEventListener');
  deviceInfoSpy = jest.spyOn(DeviceInfo, 'getModel');
});

test('Should not set pending permission due to simulator notifications error', () => {
  deviceInfoSpy.mockReturnValue('Simulator');
  const registerHandler = addEventListenerSpy.mock.calls[1][1];

  registerHandler();

  expect(store.getActions()).toEqual([pushDeviceRegistered()]);
});
```

Just access the mock object off of the spy to examine or execute the calls.

# Snapshots

Jest supports snapshot testing:

> Instead of rendering the graphical UI, which would require building the entire app, you can use a test renderer to quickly generate a serializable value for your React tree.

The first time the snapshot test is added it saves the output which you can inspect. Any time you run the tests it will diff the new output against what it has saved and if it has changed you have the choice to update it if you intended for that change or reflect on what went wrong.

# Component Snapshot: GoogleSignInButton

Here is a snapshot for a component I did as an example:

```javascript
beforeAll(() => {
  jest.spyOn(Selectors, 'getCurrentRoute').mockReturnValue('route');
});

afterAll(() => {
  Selectors.getCurrentRoute.mockRestore('Selectors');
});

it('should render correctly', () => {
  const tree = renderer.create(
    <GoogleSignInButton store={store} />
  ).toJSON();
  expect(tree).toMatchSnapshot();
});
```

# Reducer Snapshot: Debt

And it can easily be done for reducers too:

```javascript
test('START getDebtGoalDetails', () => {
  expect(debtReducer(INITIAL_STATE, getDebtGoalDetails.start())).toMatchSnapshot();
});

test('SUCCESS getDebtGoalDetails', () => {
  const payloadData = {
    payload: {
      test_key: 3,
    },
  };
  expect(debtReducer(INITIAL_STATE, getDebtGoalDetails.success(payloadData))).toMatchSnapshot();
});

test('FAIL getDebtGoalDetails', () => {
  expect(debtReducer(INITIAL_STATE, getDebtGoalDetails.fail())).toMatchSnapshot();
});
```

# Useful References

* [Jest Docs](http://facebook.github.io/jest/docs/en/api.html)
* [Jest Debugging](http://facebook.github.io/jest/docs/en/troubleshooting.html)
* [Using Jest with React Native](http://facebook.github.io/jest/docs/en/tutorial-react-native.html#content)
* [The Node Inspector](https://nodejs.org/en/docs/inspector/)
* [Jest CLI](http://facebook.github.io/jest/docs/en/cli.html#content)
