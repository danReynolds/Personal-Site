---
layout: post
title: Writing Thoughtful JavaScript Library Interfaces
image: '/images/tech/actions.jpg'
category: Tech
tags: [JavaScript, Library, ES6]
---

<!--halt-->

# Writing a JS Library

Whether you are writing your first open-source library or developing a private repo to benefit multiple teams at your company, sharing code is one of the most rewarding things to do as a developer and it is a practice at the heart of the JavaScript community. 

We will be looking at the components of a JavaScript library, the options for structuring its **Public API** and some patterns for controlling its **data access and mutation**. After comparing these options, we'll look at which of these patterns some well-known JavaScript libraries choose to follow.

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
      return this.creditCardAnalyzer() + this.bankAccountAnalyzer();
    }
});

// client.js
import CreditCalculator from 'CreditCalculator';

const creditCalculator = new CreditCalculator(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.calculateScore(); // 701
```

Our core functionality is finished! Our tool is able to calculate credit scores based on a user's bank accounts and credit cards. We publish it up to NPM and receive lots of downloads and positive feedback from initial users, hurray!

But a little while later, we start getting interesting questions from consumers of the library who are playing around with it:

1. What are these analyzer methods I see? Should I be using them?
2. How can I access the bank accounts it uses?
3. How do I update the credit cards that I passed in?

Let's classify each of these problems:

1. *What are these analyzer methods I see? Should I be using them?* - This an issue with establishing a **public** and **private** API.
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

The module pattern take advantages of JS closures to only expose the properties that the library wants to make available. This pattern allows us to use local variables that will not be exposed to consumers of the library but we can use as helpers to the private implementation. A function that is immediately executed like this is referred to as an Immediately-Invoked Function Expression (IFFE).

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

const creditCalculator = new CreditCalculator(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.calculateScore(); // 701
```

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
            this.creditCards = creditCards,

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
    * Cons: Makes clients access properties through functions

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

    * Pros: Precise control over how properties can be accessed and changed

    In the first example with `bankAccounts`, we use the `get` attribute of `defineProperty` to specify what should happen when a user accesses the `bankAccounts` property. In this case we use our function to return the underlying `bankAccounts` list. Let's go through the three additional attributes, `configurable`, `enumerable` and `writable` **(CEW)**:

    1. **configurable**: Controls whether the attributes of the property can be re-defined, changed or deleted - by changed it doesn't mean that its *value* cannot be changed, that is dictated by the *writable* attribute. Instead it means whether you can re-define the property with `defineProperty` again and whether you could alter its original CEW definition. For our getter, since we don't want it to be modified in any of these ways by the client, we will set it to `false`.
    2. **enumerable**: Controls whether enumerating an object's properties such as with `Object.keys` should return that property. Since clients should be able to discover our getter, we will set it to `true`.
    3. **writable**: Controls whether the property can be mutated with the assignment operator. Since we haven't talked about exposing a way to update our API yet, we'll default this to `false` as well.

    > Note: All of these properties default to `false`.

    In our second example with `creditCards`, we don't define a getter, but instead directly assign a `value` to our defined property. This will use the CEW defaults of false, preventing any changes to the property and is a nice short-hand.

## Data Assignment and Mutation

> How do I update the credit cards that I passed in?

There are two scenarios to consider, a user could attempt to update their credit cards by assignment, by doing something like:

```javascript
import CreditCalculator from 'CreditCalculator';

const creditCalculator = CreditCalculator();
creditCalculator.initialize(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.creditCards = ['Visa', 'Amex'];
```

or they could try to update the data by mutating an existing object:

```javascript
import CreditCalculator from 'CreditCalculator';

const creditCalculator = CreditCalculator();
creditCalculator.initialize(['Chase', 'Wells Fargo'], ['Visa', 'MasterCard']);
creditCalculator.creditCards.push(['Amex'])
```

First, let's look into how we can control **Data Assignment**:

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
    * Cons: Once again makes clients access properties through functions

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

    * Pros: Prevents access/assignment to internal properties
    * Cons: Once again makes clients access properties through functions

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

    * Pros: Internal objects are completely de-coupled from the client
    * Cons: Has performance implications for large, frequently accessed objects

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
    * Cons: Prevents internal modification of objects

    ---

> Note: A gotcha with all of the above approaches is that they do not handle deeply nested objects. There are libraries that support [deep cloning](https://lodash.com/docs/4.17.15#cloneDeep) and [freezing](https://github.com/substack/deep-freeze) of objects.

## Putting it all together

At this point we have demonstrated that JavaScript developers have a number of options for designing the different basic components of their libaries:

| Component       | Pattern                                              |
|-----------------|------------------------------------------------------|
| Public API      | underscore prefixing, module pattern                 |
| Data Access     | underscore prefixing, get methods, getter properties |
| Data Assignment | underscore prefixing, set methods, setter properties |
| Data Mutation   | spread operator, cloning, freezing                   | 

We'll now see which options some popular libraries choose in their own implementations:

## React









