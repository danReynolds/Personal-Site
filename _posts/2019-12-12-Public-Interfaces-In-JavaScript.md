---
layout: post
title: Writing Thoughtful JavaScript Library Interfaces
image: '/images/tech/actions.jpg'
category: Tech
tags: [JavaScript, Library, ES6]
---

<!--halt-->

## So you want to write a library

That's great! Sharing code is one of the most rewarding things to do as a developer and it is a practice at the heart of the JavaScript community. 

![Node Modules](https://www.google.com/url?sa=i&source=images&cd=&ved=2ahUKEwjhmsi5juzjAhWTU80KHYtmAZcQjRx6BAgBEAU&url=https%3A%2F%2Fwww.reddit.com%2Fr%2FProgrammerHumor%2Fcomments%2F6s0wov%2Fheaviest_objects_in_the_universe%2F&psig=AOvVaw0bzFixi3MDknqwc9atD3-z&ust=1565107633874251)

There are **a lot** of JavaScript projects out there and here we'll look at the patterns and practices that have emerged in JS for building responsible, well-structured libraries.

## Let's Write it!

Let's say we have some re-usable functionality that could benefit people across our team and the larger community. Today we'll use the example of a tool for calculating a credit score from a user's financial accounts.

It could look something like this:

```javascript
// GeekPurse.js
export default function GeekPurse(bankAccounts, creditCards) {
    this.creditCards = creditCards;
    this.bankAccounts = bankAccounts;
    this.creditCardAnalyzer = function creditCardAnalyzer() {
        // Do math...
    }
    this.bankAccountAnalyzer = function bankAccountAnalyzer() {
        // Do more math...
    }
    this.calculateScore = function calculateScore() {
      return this.creditCardAnalyzer() + this.bankAccountAnalyzer();
    }
});

// client.js
import GeekPurse from 'GeekPurse';

const creditCalculator = GeekPurse(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.calculateScore(); // 701
```

Our core functionality is finished! Our tool is able to calculate credit scores based on a user's bank accounts and credit cards. We publish it up to NPM and receive lots of downloads and positive feedback from initial users, hurray!

But a little while later, we start getting interesting questions from consumers of the library who are playing around with it:

1) What are these analyzer methods I see? Should I be using them?
2) How can I access the bank accounts it uses?
3) How do I update the credit cards that I passed in?

Let's classify each of these problems:

1) *What are these analyzer methods I see? Should I be using them?* - This an issue with establishing our **Public API**.
2) *How can I access the bank accounts it's using?* - This is an issue with **Data Access**.
3) *How do I update the credit cards that I passed in?* - This is an issue with **Data Mutation**.

To solve 1), we need to limit our **Public API**. Currently, all of our internal properties are exposed, which allows the client to modify things that they shouldn't be able to access and makes it too easy for them to use the module incorrectly.

The first, and simplest thing we can do is differentiate our public API from our private functions is to use **underscore prefixing**.

This is a common pattern in JS libraries, and is as simple as updating our library to this:

```javascript
export default function GeekPurse(bankAccounts, creditCards) {
    this.creditCards = creditCards;
    this.cbankAccounts = bankAccounts;
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

Some library maintainers find this to be enough of a discouragement and leave it up to consumers to know that when they use properties prefixed this way that they are risking breaking changes in future version and generally unexpected behaviour.

If we instead want to go further and not only discourage but prevent them from accessing our private implementation, we can use the **module pattern**.

## Module Pattern

```javascript
// myModule.js
export default function myModule() {
    function _privateMethod() {
        // Do internal work
    };

    return {
        publicMethod: function publicMethod() {
           _privateMethod();
        }
    }
});
// consumer.js
import myModule from './myModule';
myModule.publicMethod();
```

The module pattern uses an Immediately-Invoked Function Expression (IFFE) function to take advantage of JS closures and expose only the methods that the library want to make available.

Our implementation could now looks like this:

```javascript
// GeekPurse.js
export default (function GeekPurse() {
    const calculateScore = function calculateScore() {
       console.log(bankAccounts, creditCards)
    }
    let bankAccounts = [];
    let creditCards = [];

    return {
        bankAccounts,
        creditCards,
        initialize: function initialize(initialBankAccounts, initialCreditCards) {
            bankAccounts = initialBankAccounts;
            creditCards = initialCreditCards;
        },
        calculateScore: function publicCalculateScore() {
            return calculateScore();
        },
    };
})();
```

And the client's usage now looks like this:

```javascript
// client.js
import GeekPurse from 'GeekPurse';

const creditCalculator = GeekPurse();
creditCalculator.initialize(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.calculateScore(); // 701
```

It would be nice to maintain our original pattern of using the `new` keyword, so instead we can tweak our initial module pattern:

```javascript
// GeekPurse.js
export default (function GeekPurse() {
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
import GeekPurse from 'GeekPurse';

const creditCalculator = new GeekPurse(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.calculateScore(); // 701
```

Now that we have looked at restricting our **Public API** , let's address the second issue of **data access**:

> How can I access the bank accounts it's using?

For that, we need need to determine our preferred pattern for data access. There are a couple options:

1. **Underscored properties**: We have talked about this already for our private implementations, and we can follow the same practice for access to data properties.

```javascript
// GeekPurse.js
export default (function GeekPurse() {
    const calculateScore = function calculateScore() {
       console.log(bankAccounts, creditCards)
    }
    let bankAccounts = [];
    let creditCards = [];

    return function(initialBankAccounts, initialCreditCards) {
        bankAccounts = initialBankAccounts;
        creditCards = initialCreditCards;

        this._bankAccounts = bankAccounts;
        this.creditCards = creditCards,

        this.calculateScore = function publicCalculateScore() {
            return calculateScore();
        }
    }
})();
```

If we don't want to expose the bank accounts and do want to expose the credit cards, we can differentiate their accessors to be private or public using the prefix.

2. **Get methods**: If we want to limit our public API to not even expose those properties, we could instead write a get function.

```javascript
// GeekPurse.js
export default (function GeekPurse() {
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

Now our module's properties aren't directly exposed, but their data is still accessible.

3. **Property getters**: `Get Methods` can be cumbersome and unintuitive, so instead, JS supports customizing properties of objects to restrict whether they can be altered or removed using the [defineProperty](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/defineProperty) API.

```javascript
// GeekPurse.js
export default (function GeekPurse() {
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

In the first example with `bankAccounts`, we use the `get` attribute of `defineProperty` to specify what should happen when a user does `.bankAccounts`. In this case we use our function to return the underlying `bankAccounts` list. The 3 additional attributes `configurable`, `enumerable` and `writable` (CEW). Let's go through them in order:

1. **configurable**: Controls whether the attributes of the property can be re-defined, changed or deleted - by changed it doesn't mean that its *value* cannot be mutated, that is dictated by the *writable* attribute. Instead it means whether you can re-define the property with `defineProperty` again and whether you could alter its original CEW definition. For our getter, since we don't want it to be modified in any of these ways by the client, we will set it to `false`.
2. **enumerable**: Controls whether enumerating an object's properties such as with `Object.keys` should return that property. Since clients should be able to discover our getter, we will set it to `true`.
3. **writable**: Controls whether the property can be mutated with the assignment operator. Since we haven't talked about exposing a way to update our API yet, we'll default these to `false` as well.

> Note: All of these properties default to `false`.

In our second example with `creditCards`, we don't define a getter, but instead directly assign a `value` to our defined property. This will use the CEW defaults of false, preventing any changes to the property and is a nice short-hand.

Now that we've considered options for building our data accessors, we will consider the question around **data mutation**:

> How do I update the credit cards that I passed in?

Let's go through the ways we can control data mutation:

1. **Set methods**: Similarly to a `get`-prefixed method, we could write a simple setter method in order to restrict mutation to our internal properties:


```javascript
// GeekPurse.js
export default (function GeekPurse() {
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

But similarly to the `get` method, this isn't a common practice in JS.

2. **Property setters**: the `defineProperty` API also allows us to define how our properties can be set.



// Talk about this below somewhere to differentiate assignment and mutation, then talk about freeze vs returning new thing every time,
make a table of all the things we discussed.

There are two types of data mutation to consider when addressing this question:

1. Re-assignment using the assignment `=` operator
2. Mutation of objects using assignment to their properties, or mutative APIs like `Array.push`



