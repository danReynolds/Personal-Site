---
layout: post
title: Building JavaScript Libraries
image: '/images/tech/library.jpg'
category: Tech
tags: [JavaScript, Library, ES6]
---

A walk-through of some of the API decisions to consider when writing a JavaScript library.

<!--halt-->

# Writing a JS Library

Whether you are writing your first open-source library or developing a private repo to benefit multiple teams at your company, sharing code is one of the most rewarding things to do as a developer and it is a practice at the heart of the JavaScript community. 

We will be doing a walk-through of the components of a JavaScript library including some options for structuring its **Public API**, as well as tools for controlling its **data access and mutation**. After comparing these options, we'll look at which of these patterns some well-known JavaScript libraries choose to follow.

## Getting Started

Let's say we have some valuable tool that we want to share with the larger community. Here we'll use the example of a tool for calculating a credit score from a user's financial accounts.

It could look something like this:

```javascript
// CreditCalculator.js
export default function CreditCalculator(bankAccounts, creditCards) {
    this.creditCards = creditCards;
    this.bankAccounts = bankAccounts;
    this.creditCardAnalyzer = function creditCardAnalyzer() {
        // Do math...
    }
    this.bankAccountAnalyzer = function bankAccountAnalyzer() {
        // Do more math...
    }
    this.calculateScore = function calculateScore() {
      // I'm sure it's just this simple...
      return this.creditCardAnalyzer() + this.bankAccountAnalyzer();
    }
});

// client.js
import CreditCalculator from 'CreditCalculator';
const creditCalculator = new CreditCalculator(
  ['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']
);
creditCalculator.calculateScore(); // 800
```

Our core functionality is finished! Our tool is able to calculate credit scores based on a user's bank accounts and credit cards. We publish it up to NPM and receive lots of downloads and positive feedback from initial users, hurray!

But a little while later, we start getting interesting questions from consumers of the library who are playing around with it:

1. I called this analyzer method but it didn't work, what's wrong?
2. How can I access the bank accounts it uses?
3. How do I update the credit cards that I passed in?

Let's classify each of these problems:

1. *I called this analyzer method but it didn't work, what's wrong?* - The user shouldn't be calling the analyzer functions, this is an issue with establishing a **public** API.
2. *How can I see which banks it is using in its calculation?* - This is an issue with **data access**.
3. *How do I update the credit cards that I passed in?* - This is an issue with **data assignment and mutation**

To answer the first question, we need to control what functionality we want to expose to the client. Currently, all of our internal properties are exposed, which makes it too easy for them to use the module incorrectly.

## Establishing a Public API

> What are these analyzer methods I see? Should I be using them?

The first, and simplest thing we can do to differentiate our public and private implementation is to use **underscore prefixing**.

This is a common pattern in JS libraries, and is simple to do:

```javascript
export default function CreditCalculator(bankAccounts, creditCards) {
    this.creditCards = creditCards;
    this.bankAccounts = bankAccounts;
    this._creditCardAnalyzer = function creditCardAnalyzer() {
        // Do math...
    }
    this._bankAccountAnalyzer = function bankAccountAnalyzer() {
        // Do more math...
    }
    this.calculateScore = function calculateScore() {
      return this.creditCardAnalyzer() + this.bankAccountAnalyzer();
    }
});
```

Some library maintainers find this, along with private or deprecated documentation using tools like [JSDoc](https://github.com/jsdoc/jsdoc) to be enough of a discouragement. They leave it up to consumers to know that when they use properties prefixed this way, they are risking breaking changes in future version and generally may encounter unexpected behaviour.

If we instead want to go further and not only discourage but prevent them from accessing our private implementation, we can use the **module pattern**.

## Module Pattern

The module pattern take advantages of closures to only expose the properties that the library wants to make available.

The function below is called right away so that it can create a closure over the local `bankAccounts` and `creditCards` variables and use them throughout the implementation without them ever being exposed.

```javascript
// CreditCalculator.js
export default (function CreditCalculator() {
    const calculateScore = function calculateScore() {
       console.log(bankAccounts, creditCards)
    }
    let bankAccounts = [];
    let creditCards = [];

    return function(initialBankAccounts, initialCreditCards) {
        bankAccounts = initialBankAccounts;
        creditCards = initialCreditCards;

        this.bankAccounts = bankAccounts;
        this.creditCards = creditCards,

        this.calculateScore = function publicCalculateScore() {
            return calculateScore();
        }
    }
})();
```

```javascript
// client.js
import CreditCalculator from 'CreditCalculator';
const creditCalculator = new CreditCalculator(
  ['Chase', 'Wells Fargo'],
  ['Visa', 'MasterCard']
);
creditCalculator.calculateScore(); // 801
```

A function that is immediately executed like this is referred to in JavaScript as an Immediately-Invoked Function Expression (IIFE).

## Data Access

> How can I see which banks it is using in its calculation?

There are different ways a library can choose to let clients access its public data.

1. **Underscore prefixing**: We can follow the same pre-fixing practice for access to public vs private data properties.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            this._bankAccounts = bankAccounts;
            this._creditCards = creditCards,

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Simplicity
    * Cons: Does not actually prevent access to private properties

    ---

2. **Get methods**: If we want to limit our public API to not directly expose our internal properties, we could instead write a get-prefixed wrapper function.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            this.getBankAccounts = function getBankAccounts() {
                return bankAccounts;
            };

            this.getCreditCards = function getBankAccounts() {
                return creditCards;
            };

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Prevents access/assignment to internal properties
    * Cons: Makes clients access properties through indirect proxy functions

    ---

3. **Property getters**: JS supports customizing how properties can be accessed, modified and removed using the [defineProperty](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/defineProperty) API.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            Object.defineProperty(this, 'bankAccounts', {
                configurable: false,
                enumerable: true,
                writable: false,
                get: function getBankAccounts() {
                    return bankAccounts;
                }
            });

            Object.defineProperty(this, 'creditCards', {
                value: creditCards,
            });

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Precise control over how properties can be accessed

    In the first example we use the `get` attribute of `defineProperty` to specify what should happen when a user accesses the `bankAccounts` property. In this case we use our function to return the underlying `bankAccounts` list. Let's go through the three additional attributes, `configurable`, `enumerable` and `writable` **(CEW)**:

    1. **configurable**: Controls whether the attributes of the property can be re-defined, changed or deleted - by changed it doesn't mean that its *value* cannot be changed, that is dictated by the *writable* attribute. Instead it means whether you can re-define the property with `defineProperty` again and whether you could alter its original CEW definition. For our getter, since we don't want it to be modified in any of these ways by the client, we will set it to `false`.
    2. **enumerable**: Controls whether enumerating an object's properties such as with `Object.keys` should return that property. Since clients should be able to discover our getter, we will set it to `true`.
    3. **writable**: Controls whether the property can be written with the assignment operator. Since we haven't talked about exposing a way to update our API yet, we'll default this to `false` as well.

    > Note: All of these properties default to `false`.

    In our second example with `creditCards`, we don't define a getter, but instead directly assign a `value` to our defined property. This will use the CEW defaults of false, preventing any changes to the property and is a nice short-hand.

## Data Assignment and Mutation

> How do I update the credit cards that I passed in?

There are two scenarios to consider, a user could attempt to update their credit cards by assignment, by doing something like:

```javascript
import CreditCalculator from 'CreditCalculator';

const creditCalculator = new CreditCalculator(
  ['Chase', 'Wells Fargo'],
  ['Visa', 'MasterCard']
);
creditCalculator.creditCards = ['Visa', 'Amex'];
```

or they could try to update the data by mutating an existing object:

```javascript
import CreditCalculator from 'CreditCalculator';

const creditCalculator = new CreditCalculator(
  ['Chase', 'Wells Fargo'],
  ['Visa', 'MasterCard']
);
creditCalculator.creditCards.push(['Amex'])
```

First, let's look into how we can control **data assignment**:

1. **Set methods**: Similarly to a `get`-prefixed function, we could write a simple set wrapper function.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            this.setBankAccounts = function setBankAccounts(newBankAccounts) {
                bankAccounts = newBankAccounts;;
            };

            this.setCreditCards = function setCreditCards(newCreditCards) {
                creditCards = newCreditCards;
            };

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Prevents access/assignment to internal properties
    * Cons: Once again makes clients interact with properties through indirect functions

    ---

2. **Property setters**: the `defineProperty` API also allows us to define how to assign properties.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            Object.defineProperty(this, 'bankAccounts', {
                enumerable: true,
                get: function() {
                    return bankAccounts;
                },
                set: function(newBankAccounts) {
                    bankAccounts = newBankAccounts;
                }
            });

            Object.defineProperty(this, 'creditCards', {
                enumerable: true,
                get: function() {
                    return creditCards;
                },
                set: function(newCreditCards) {
                    creditCards = newCreditCards;
                }
            });

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Allows for direct, fully-customizable assignment of properties

    ---

    > Note: We no longer specify the `writable` attribute, since it would conflict with the `set` attribute.

Next let's look at some options for controlling **Data Mutation**:

1. **Spread Operator**: The spread operator `{...}`/`[...]` is a useful tool for making data immutable.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = [];
        let creditCards = [];

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            Object.defineProperty(this, 'bankAccounts', {
                enumerable: true,
                get: function() {
                    return [...bankAccounts];
                },
                set: function(newBankAccounts) {
                    bankAccounts = newBankAccounts;
                }
            });

            Object.defineProperty(this, 'creditCards', {
                enumerable: true,
                get: function() {
                    return [...creditCards];
                },
                set: function(newCreditCards) {
                    creditCards = newCreditCards;
                }
            });

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Simple way to prevent mutation of internal properties
    * Cons: Difficult to use for nested objects

    ---

2. **Cloning**: Libraries like Lodash have utilities for [cloning](https://lodash.com/docs/4.17.15#clone) objects.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        const calculateScore = function calculateScore() {
        console.log(bankAccounts, creditCards)
        }
        let bankAccounts = Object.freeze([]);
        let creditCards = [Object.freeze([]);

        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;

            Object.defineProperty(this, 'bankAccounts', {
                enumerable: true,
                get: function() {
                    return _.clone(bankAccounts);
                },
                set: function(newBankAccounts) {
                    bankAccounts = Object.freeze(newBankAccounts);
                }
            });

            Object.defineProperty(this, 'creditCards', {
                enumerable: true,
                get: function() {
                    return _.clone(creditCards);
                },
                set: function(newCreditCards) {
                    creditCards = Object.freeze(newCreditCards);
                }
            });

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    * Pros: Internal objects are not exposted to the client
    * Cons: Has performance implications for large, frequently accessed objects, loses referential equality checking

    ---

3. **Freezing**: The [Object.freeze](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/freeze) API can be used to prevent mutation of properties.

    ```javascript
    // CreditCalculator.js
    export default (function CreditCalculator() {
        return function(initialBankAccounts, initialCreditCards) {
            bankAccounts = Object.freeze([...initialBankAccounts]);
            creditCards = Object.freeze([...initialCreditCards]);

            Object.defineProperty(this, 'bankAccounts', {
                enumerable: true,
                get: function() {
                    return bankAccounts;
                },
                set: function(newBankAccounts) {
                    bankAccounts = Object.freeze([...newBankAccounts]);
                }
            });

            Object.defineProperty(this, 'creditCards', {
                enumerable: true,
                get: function() {
                    return creditCards;
                },
                set: function(newCreditCards) {
                    creditCards = Object.freeze([...newCreditCards]);
                }
            });

            this.calculateScore = function publicCalculateScore() {
                return calculateScore();
            }
        }
    })();
    ```

    Freezing objects prevents adding, removing, writing or re-configuration of a properties CEW attributes. For an array like in our example, that means that mutative APIs like `Array.push` will not update the object.

    * Pros: Referential equality maintained across accesses
    * Cons: Prevents internal modification of objects (could also be a win depending on your opinions around data immutability)

    ---

> Note: A gotcha with all of the above approaches is that they do not handle deeply nested objects. There are libraries that support [deep cloning](https://lodash.com/docs/4.17.15#cloneDeep) and [freezing](https://github.com/substack/deep-freeze) of objects.

## Putting it all together

At this point we have demonstrated that JavaScript developers have a number of options for designing the different basic components of their libaries:

| Component       | Pattern                                                |
|-----------------|--------------------------------------------------------|
| Public API      | underscore prefixing, module pattern, property getters |
| Data Access     | underscore prefixing, get methods, property getters    |
| Data Assignment | underscore prefixing, set methods, setter properties   |
| Data Mutation   | spread operator, cloning, freezing                     | 

We'll now see which options some popular libraries choose in their own implementations:

## Case Study: [React](https://github.com/facebook/react)

### Data Access, Assignment and Mutation

React supplies classes like Component and PureComponent to create its UI. Here is an [example](https://reactjs.org/docs/forms.html#the-textarea-tag)  from the React docs:

```javascript
import React from 'react';

class EssayForm extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      value: 'Please write an essay about your favorite DOM element.'
    };

    this.handleChange = this.handleChange.bind(this);
    this.handleSubmit = this.handleSubmit.bind(this);
  }

  handleChange(event) {
    this.setState({value: event.target.value});
  }

  handleSubmit(event) {
    alert('An essay was submitted: ' + this.state.value);
    event.preventDefault();
  }

  render() {
    return (
      <form onSubmit={this.handleSubmit}>
        <label>
          Essay:
          <textarea value={this.state.value} onChange={this.handleChange} />
        </label>
        <input type="submit" value="Submit" />
      </form>
    );
  }
}
```

Here they've defined a form with an editable text-area that a user can type in. If the user has typed something, it gets stored in the `state` data accessor on that component instance.

The [React docs](https://reactjs.org/docs/state-and-lifecycle.html#do-not-modify-state-directly) make clear that `state` is not to be mutated directly:

![reactState](/images/tech/react-state.png)

As a React developer one of the first things you learn is to instead call the `setState` API to change your component's state. This is **not**, however, enforced by the library and the following lines will execute fine:

```javascript
this.state.newThing = "this is not a good idea..."; 
this.state = "yea you shouldn't do this either...";
```

While this direct assignment will not cause any immediate errors, since it was not done through `setState`, React will not know to re-render and since it is not an object, it will blow up at some later execution point.

React has chosen in their API to not limit assignment and mutation in any way for its properties. Instead, it generally relies on convention, its comprehensive documentation and the downstream errors you will get if you were to make a change like this to keep developers in check.

React **does** call out erroneous assignment at the end of the [componentWillMount](https://github.com/facebook/react/blob/1022ee0ec140b8fce47c43ec57ee4a9f80f42eca/packages/react-reconciler/src/ReactFiberClassComponent.js#L730) lifecycle event:

```javascript
if (typeof instance.componentWillMount === 'function') {
  instance.componentWillMount();
}

if (oldState !== instance.state) {
    if (__DEV__) {
      warningWithoutStack(
        false,
        '%s.componentWillMount(): Assigning directly to this.state is ' +
          "deprecated (except inside a component's " +
          'constructor). Use setState instead.',
        getComponentName(workInProgress.type) || 'Component',
      );
    }
    classComponentUpdater.enqueueReplaceState(instance, instance.state, null);
  }
}
```

Here in development mode, it calls out that the `state` property should not be mutated after running the client's defined `componentWillMount` method. It was a common error for developers learning the library to mutate state in `componentWillMount` directly, and React calls out that this should never be done outside of the `constructor`, the one place where the `state` property can be initialized with direct assignment.

### Public API

React class components choose to underscore prefix some private properties:

```javascript
render() {
    console.log(Object.keys(this));
    /**
        0: "props"
        1: "context"
        2: "refs"
        3: "updater"
        13: "state"
        14: "_reactInternalFiber"
        15: "_reactInternalInstance"
     */
}
```

If you haven't seen the `_reactInternalFiber` property before, that's the goal. React has pre-fixed it with an underscore to signify that clients should generally avoid touching that property.

To check if they are using the `defineProperty` getters approach of hiding some internal properties, we can use the [`Object.getOwnPropertyNames`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/getOwnPropertyNames) API which returns all of the own property keys of an object, even if it was set with `enumerable` false.

We can write a quick function to gather all inherited properties by doing this recursively for an object and its prototype:

```javascript
const getAllProperties = (obj) => { 
  const props = new Set(Object.getOwnPropertyNames(obj));
  const proto = Object.getPrototypeOf(obj);
  if (proto) {
    getAllProperties(proto).forEach(prop => props.add(prop));
  }
  return props;
}
```

Here is what we get when we run it on an instance of a React component:

```javascript
render() {
    console.log(getAllProperties(this));
    /**
        0: "props"
        1: "context"
        2: "refs"
        3: "updater"
        13: "state"
        14: "_reactInternalFiber"
        15: "_reactInternalInstance"
        16: "constructor"
        20: "isReactComponent"
        21: "setState"
        22: "forceUpdate"
        23: "isPureReactComponent"
        24: "isMounted"
        25: "replaceState"
        26: "__defineGetter__"
        27: "__defineSetter__"
        28: "hasOwnProperty"
        29: "__lookupGetter__"
        30: "__lookupSetter__"
        31: "isPrototypeOf"
        32: "propertyIsEnumerable"
        33: "toString"
        34: "valueOf"
        35: "__proto__"
        36: "toLocaleString"
     */
}
```

How many of these were intended to be exposed to us? We can check that with the [propertyIsEnumerable](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/propertyIsEnumerable) API:

```javascript
const getAllPropertiesWithEnumerability = (obj) => { 
  const props = new Set(Object.getOwnPropertyNames(obj)
    .map(prop => `${prop}-${obj.propertyIsEnumerable(prop)}`));
  const proto = Object.getPrototypeOf(obj);
  if (proto) {
    getAllPropertiesWithEnumerability(proto).forEach(prop => props.add(prop));
  }
  return props;
}
```

Which now gives us:

```javascript
render() {
    console.log(getAllProperties(this));
    /**
        0: "props-true"
        1: "context-true"
        2: "refs-true"
        3: "updater-true"
        13: "state-true"
        14: "_reactInternalFiber-true"
        15: "_reactInternalInstance-true"
        20: "constructor-true"
        21: "isReactComponent-true"
        22: "setState-true"
        23: "forceUpdate-true"
        24: "isPureReactComponent-true"
        25: "isMounted-false"
        26: "replaceState-false"
        27: "__defineGetter__-false"
        28: "__defineSetter__-false"
        29: "hasOwnProperty-false"
        30: "__lookupGetter__-false"
        31: "__lookupSetter__-false"
        32: "isPrototypeOf-false"
        33: "propertyIsEnumerable-false"
        34: "toString-false"
        35: "valueOf-false"
        36: "__proto__-false"
        37: "toLocaleString-false"
     */
}
```

Some of these properties are inherited from base JavaScript objects like `isPrototypeOf` or `toString`, but if we look at some of React's own properties like `isMounted` or `replaceState`, we'll notice that React made the decision to restrict access to those APIs by setting them to `enumerable: false` which you can see here in [the source](https://github.com/facebook/react/blob/18d2e0c03e4496a824fdb7f89ea2a3d60c30d49a/packages/react/src/ReactBaseClasses.js#L118).

As the documentation explains, React did this because those APIs have since been deprecated.

Let's highlight how React chose to manage its API:

| Component       | Pattern                                                        |
|-----------------|----------------------------------------------------------------|
| **Public API**  | **underscore prefixing**, module pattern, **property getters** |
| Data Access     | underscore prefixing, get methods, property getters            |
| Data Assignment | underscore prefixing, set methods, setter properties           |
| Data Mutation   | spread operator, cloning, freezing                             | 

Overall, React is pretty liberal with its API exposure, with no controls over data assignment or mutation and limited usage of underscore pre-fixing and enumerability controls.

## Case Study: [Moment](https://momentjs.com/)

Moment is a popular library for viewing and working with dates in JavaScript.

Usage of the library might look something like:

```javascript
import moment from 'moment';

const date = moment();
console.log(date.format('YYYY-DD-MM')); // 2019-30-10
```

### Public API

Moment is composed of a wide variety of utility functions for manipulating dates that all live on the moment prototype.

For organization, its source implementation is broken into a folder structure:

```
src/
  lib/
    modules/
      moment/
        from.js
        now.js
        ...
      format/
        ...
      parse/
        ...
```

This folder structure makes a lot of sense during development, but what what it ends up exposing after it is processed for production is a variation of the module pattern we've looked at before. Here is a condensed version of it that highlights the pattern:

```javascript
(function (global, factory) {
    typeof exports === 'object' && typeof module !== 'undefined' ?
      module.exports = factory() :
      typeof define === 'function' && define.amd ?
        define(factory) :
        global.moment = factory()
}(this, (function () { 'use strict';

    var hookCallback;

    function hooks () {
      return hookCallback.apply(null, arguments);
    }

    // This is done to register the method called with moment()
    // without creating circular dependencies.
    function setHookCallback (callback) {
      hookCallback = callback;
    }

    // Moment prototype object
    function Moment(config) {
        copyConfig(this, config);
        this._d = new Date(config._d != null ? config._d.getTime() : NaN);
        if (!this.isValid()) {
            this._d = new Date(NaN);
        }
        // Prevent infinite loop in case updateOffset creates new moment
        // objects.
        if (updateInProgress === false) {
            updateInProgress = true;
            hooks.updateOffset(this);
            updateInProgress = false;
        }
    }

    function calendar (key, mom, now) {
        var output = this._calendar[key] || this._calendar['sameElse'];
        return isFunction(output) ? output.call(mom, now) : output;
    }

    var proto = Moment.prototype;

    proto.add               = add;
    proto.calendar          = calendar;
    proto.clone             = clone;
    proto.diff              = diff;

    function createFromConfig (config) {
        var res = new Moment(checkOverflow(prepareConfig(config)));
        if (res._nextDay) {
            // Adding is smart enough around DST
            res.add(1, 'd');
            res._nextDay = undefined;
        }

        return res;
    }

    function createLocalOrUTC (input, format, locale, strict, isUTC) {
        var c = {};

        if (locale === true || locale === false) {
            strict = locale;
            locale = undefined;
        }

        if ((isObject(input) && isObjectEmpty(input)) ||
                (isArray(input) && input.length === 0)) {
            input = undefined;
        }
        // object construction must be done this way.
        // https://github.com/moment/moment/issues/1423
        c._isAMomentObject = true;
        c._useUTC = c._isUTC = isUTC;
        c._l = locale;
        c._i = input;
        c._f = format;
        c._strict = strict;

        return createFromConfig(c);
    }

    function createLocal (input, format, locale, strict) {
      return createLocalOrUTC(input, format, locale, strict, false);
    }

    setHookCallback(createLocal);

    hooks.fn                    = proto;
    hooks.min                   = min;
    hooks.max                   = max;
    hooks.now                   = now;
    hooks.utc                   = createUTC;
    hooks.unix                  = createUnix;
    hooks.months                = listMonths;

    return hooks;
})));
```

You can check out the full source [here](https://github.com/moment/moment/blob/96d0d6791ab495859d09a868803d31a55c917de1/moment.js).

Let's take a moment to digest this code. The outer-most function is another immediately-invoked function expression **(IIFE)**. It is immediately called with a passed-in factory function that holds a closure over all of the variables and functions that the library uses.

For an ES6 import statement like `import moment from 'moment'`, what is exposed is the return value of the factory as an export: `module.exports = factory()`.

This return value is a function which has a number of public utilities on it, like `months`:

```javascript
import moment from 'moment';

console.log(moment.months());
0: "January"
1: "February"
2: "March"
3: "April"
4: "May"
5: "June"
6: "July"
7: "August"
8: "September"
9: "October"
10: "November"
11: "December"
```

All the helper functions and variables that enable this functionality are not exposed on the object, allowing it to hide its internal implementation.

The function itself can be called to perform the default behaviour of the moment library, which is to instantiate a `new Moment` object:

```javascript
import moment from 'moment';

console.log(moment());
_d: Wed Oct 30 2019 17:20:39 GMT-0400 (Eastern Daylight Time) {}
_isAMomentObject: true
_isUTC: false
_isValid: true
_locale: Locale {_calendar: {…}, …}
_pf: {empty: false, unusedTokens: Array(0)…}
_z: null
```

### Data Access and Mutation

As seen above, when it does expose objects like its `Moment` function, it heavily relies on the use of underscored properties to make clear its public and private API.

Its internal date is stored under the `_d` property, which is only restricted by the underscoring and could be mutated or re-assigned if a client really wanted (but shouldn't).

Putting it all together, Moment's API summary looks like this:

| Component       | Pattern                                                        |
|-----------------|----------------------------------------------------------------|
| **Public API**  | **underscore prefixing**, **module pattern**, property getters |
| Data Access     | **underscore prefixing**, get methods, property getters        |
| Data Assignment | underscore prefixing, set methods, setter properties           |
| Data Mutation   | spread operator, cloning, freezing                             | 

It is a clear example of a library that uses the module pattern to limit its API and chooses to rely on underscored properties to differentiate its underlying implementation.


## Find What Works for You

JavaScript and its ecosystem doesn't have just one right way to do something. The goal of this walk-through is to highlight some of the tools and patterns JavaScript developers have available to them for managing the way they build their libraries.

The decisions a library owner makes in exposing their API and controlling access and mutation of its data can have profound impact on the usability, maintainability and ultimately the success of the library within teams, organizations and the larger community.

There are more case studies to come, feel free to reach out on [Twitter](https://twitter.com/TheDerivative) to suggest any that you would like to see talked about.









    















