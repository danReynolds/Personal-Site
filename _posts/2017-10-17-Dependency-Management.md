---
layout: post
title: Dealing with Dependency Resolution
image: '/images/tech/yarn-npm.jpg'
category: Tech
tags: [project, yarn, javascript, dependencies]
---

The upgrade of React to version 16 caused issues in our repos with dependencies
that were relying on deprecated functionality that had now been removed.

<!--halt-->

# Optimistic Versioning

When React 16 came out, it caused problems on some of our private node modules that had a React version
specified of `>= 14.0.0`.

React 16 had incompatible changes such as the removal of `PropTypes` to a separate module. Many of our dependencies were still using the PropTypes from React and when they started pulling in React 16
things started to break.

This problem manifested itself in one of our tests:

```javascript
TypeError: Cannot read property 'oneOfType' of undefined
```

`oneOfType` is a property off of `PropTypes` which is now in its own package.

The easiest fix was to bump the packages that had broken to use a react dependency of `^14.0.0 | ^15.0.0` and that's what we did, but the problem there is that it forces consumers of the packages to
upgrade to the latest versions of those dependencies, versions that likely might have incompatible APIs and at least require testing for each module that was changed.

We had a large number of modules to do this for, so asking teams to make that change immediately is not a great option.

# Use the Package Manager Luke

Like I had talked about in a [previous post](https://danreynolds.ca/tech/2017/10/16/Upgrading-Package-Manager/), some of our teams use npm and some use Yarn.

The solution to our dependency problem could be achieved using either package manager, but it turns out that it had to be done in different ways.

One of the repos that was using Yarn had this problem because a sub-dependency required React `>= 14.0.0`, and this caused the package to pull in React 16.0.0 even though it had a dev dependency of React `^15.4.2` explicitly in the root `package.json`.

Running Yarn and looking in the `yarn.lock` it was clear that it had resolved two versions of React:

```lock
react@16.0.0-alpha.12:
  version "16.0.0-alpha.12"
  resolved "https://registry.yarnpkg.com/react/-/react-16.0.0-alpha.12.tgz#8c59485281485df319b6f77682d8dd0621c08194"
  dependencies:
    create-react-class "^15.5.2"
    fbjs "^0.8.9"
    loose-envify "^1.1.0"
    object-assign "^4.1.0"
    prop-types "^15.5.6"

react@>=14.0.0:
  version "15.6.1"
  resolved "https://registry.yarnpkg.com/react/-/react-15.6.1.tgz#baa8434ec6780bde997cdc380b79cd33b96393df"
  dependencies:
    create-react-class "^15.6.0"
    fbjs "^0.8.9"
    loose-envify "^1.1.0"
    object-assign "^4.1.0"
    prop-types "^15.5.10"
```

and running `yarn list react` returned:

```
├─ @nerdwallet/nw-client-lib@2.36.2
│  ├─ @nerdwallet/react-typography@7.0.2
│  │  └─ react@15.6.2
│  └─ react@16.0.0
├─ @nerdwallet/react-select@7.1.0
│  └─ react@16.0.0
├─ @nerdwallet/react-typography@6.1.2
│  └─ react@16.0.0
└─ react@15.6.2
```

While the sub-dependency would be satisfied by version `15.6.1` also, it did not use the parent dependency's version and resolved its own, the latest compatible match being `16.0.0-alpha.12`.

After looking into how Yarn resolves dependencies, a great explanation was offered [here](https://github.com/yarnpkg/yarn/issues/3951#issuecomment-316424639) by Yarn contributor arcanis.

He goes on to offer insight into how dependencies requiring a certain version determine which one to use:

> a dependencies entry means that this package MUST be able to require a package of version $VERSION. There's absolutely no mention about this version being compatible with any other. If you need this behavior, then you have to use peerDependencies, which provide the extra guarantee that the selected version MUST be the same as the one provided by the parent package

So just because our sub-dependency was for `>= 14.0.0` does not mean that it will use the parent dependency of `^15.0.0` in the root `package.json`.

Yarn has a hoister which hoists and resolves dependencies and is really composed of two parts:

1. The **optimizer**, which runs during resolution and tries to resolve duplicate dependencies that have already been satisfied by previous resolution requests, but which has no real knowledge of parent/child dependency relationships. It does not know that the parent has a dependency of `^15.4.2` and the parent does not know the child has a dependency of `>= 14.0.0`.

2. The **hoister**, which runs once resolution and optimization has completed and merges dependencies that were resolved in the previous step of the *exact* same version, regardless of their original desired ranges.

In our case, after step 1 we would have the two react versions and since they are different versions, the hoister does not know that they came from compatible ranges and does not merge them.

This is actually different behavior from what happens in npm. Taking the same project with Yarn 1.2.1, we tried running `npm install` on version `5.5.1`. With npm, we got the following `package-lock.json` entry:

```json
"react": {
  "version": "15.6.2",
  "resolved": "https://registry.npmjs.org/react/-/react-15.6.2.tgz",
  "integrity": "sha1-26BDSrQ5z+gvEI8PURZjkIF5qnI=",
  "requires": {
    "create-react-class": "15.6.2",
    "fbjs": "0.8.16",
    "loose-envify": "1.3.1",
    "object-assign": "4.1.1",
    "prop-types": "15.6.0"
  }
}
```

and running `npm list react` we get:

```
├─┬ @nerdwallet/nw-client-lib@2.36.2
│ ├─┬ @nerdwallet/react-colors@4.1.3
│ │ └── react@15.6.2  deduped
│ ├─┬ @nerdwallet/react-icon@5.1.3
│ │ └── react@15.6.2  deduped
│ ├─┬ @nerdwallet/react-media-queries@3.1.2
│ │ └── react@15.6.2  deduped
│ ├─┬ @nerdwallet/react-star-rating@2.0.4
│ │ └── react@15.6.2  deduped
│ ├─┬ @nerdwallet/react-textarea@2.0.4
│ │ └── react@15.6.2  deduped
│ └─┬ @nerdwallet/react-typography@7.0.2
│   └── react@15.6.2  deduped
├─┬ @nerdwallet/react-button@8.0.3
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-colors@5.1.2
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-formatted-input@7.0.3
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-input@8.2.3
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-popover@10.0.3
│ ├─┬ @nerdwallet/react-animations@2.0.2
│ │ └── react@15.6.2  deduped
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-progress-bar@1.0.3
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-select@7.1.0
│ ├─┬ @nerdwallet/react-colors@3.1.0
│ │ └── react@15.6.2  deduped
│ ├─┬ @nerdwallet/react-icon@3.0.0
│ │ └── react@15.6.2  deduped
│ └── react@15.6.2  deduped
├─┬ @nerdwallet/react-typography@6.1.2
│ ├─┬ @nerdwallet/react-colors@3.1.0
│ │ └── react@15.6.2  deduped
│ └── react@15.6.2  deduped
└── react@15.6.2
```

npm indicates what version the package is using and if it already found a compatible version it marks it as *deduped*.

We can see that it is just using `15.6.12` given that it also matches the sub-dependency requirement of a version `>= 14.0.0`.

That seems like the best behavior in my opinion, since we do not need two versions of react installed. It makes sense that it should work with both packages given that the author of the sub-dependency said that `15.6.2` is within the valid dependency ranges.

After running our tests again with the npm installation it all worked, but we still had to fix the problem for Yarn users.

## Yarn Resolutions

Yarn 1.0 released a feature I talked about in my last post called `resolutions`. Here is a quick description of the problem they are solving from the Yarn 1.0 launch:

> Occasionally, packages will receive important bug fixes or critical security updates that need to be adopted as soon as possible. Unfortunately, your project may not be the direct consumer of those dependencies, but rather will use them through a few layers of transient dependencies. In such cases, you'll be forced to either wait until your direct dependency is updated, or fork it and update the dependencies manually until a new release.

That sounds great! We have a few layers of dependencies that need React set to a specific version.

We can now specify a `resolutions` block in your `package.json` that instructs Yarn to use certain versions of sub-dependencies regardless of the version requested in their original dependency sets.

By adding the following to our `package.json`:

```javascript
"resolutions": {
  "react": "^15.4.2"
}
```

We enforce that only one dependency of react is resolved and that it matches our requirement of less than version 16. Now when I look at the `yarn.lock` we have a single React entry:

```
react@>=0.14.0, "react@^0.14.0 || ^15.0.0", react@^15.4.2:
  version "15.6.2"
  resolved "https://registry.yarnpkg.com/react/-/react-15.6.2.tgz#dba0434ab439cfe82f108f0f511663908179aa72"
  dependencies:
    create-react-class "^15.6.0"
    fbjs "^0.8.9"
    loose-envify "^1.1.0"
    object-assign "^4.1.0"
    prop-types "^15.5.10"
```

and running `yarn list react` again is a single line:

```
└─ react@15.6.2
```

## Takeaway

The tests are now passing with the correct version of React resolved using both Yarn and npm. The first key things to consider is to be careful of optimistic versioning of dependencies greater than any particular version. Over time we will pull in the upgraded versions of our dependencies that have corrected this problem in their `package.json` and then remove the blanket resolution.

The second thing to note is that Yarn and npm resolve packages differently. It was surprising when we realized that some projects using the same packages were broken and some weren't because of the React upgrade. Choose whichever system works best for you and remember to check the implementation differences between the two package managers before taking anything for granted.
