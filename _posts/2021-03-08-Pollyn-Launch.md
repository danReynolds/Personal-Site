---
layout: post
title: Launch Time! Introducing Pollyn
image: '/images/tech/pollyn-banner.jpeg'
category: Tech
tags: [Flutter, Pollyn]
---

A dive into why and how I went about building Pollyn - the referral sharing app.

<!--halt-->

## What is Pollyn?

Pollyn is a referral sharing app where people can post referral codes and let their friends use them when they need them. You can choose to have your referrals visible to the larger community or just your friends that you add in the app, but you will always see referrals from your friends first.

If you have referral codes sitting around collecting dust or would like to explore what bonuses are out there for services you're interested in feel free to [check it out](https://www.pollyn.app/)

Don't hesitate to give feedback in the app or at [dan@pollyn.app](mailto:dan@pollyn.app) and if you have a product, design or business background and would like to collaborate, I'd welcome folks to reach out.

## Why a referral sharing app?

Firstly, I've always found that the referral codes that companies give me end up going largely unused. I either assume my friends have already signed up for a service and don't share it to them or when I do share, they forget to use it or can't remember where/when I sent it to them. The interactions I've had where referral codes do actually get used go something along the lines of a friend mentioning they might sign up for something followed by a mad scramble to find my code and give it to them before missing the chance to earn a nice referral bonus.

On the referral owner side, that's not a great system, and it's a shame because as I've discovered through working in the referral code space that there are a lot of valuable codes out there that could save people good money per year and also give them the warm fuzzies knowing that they helped their friends save money too. On the referral consumer side, it's also not a great landscape at the moment as most sites are just walls of unverified codes that could either be old or inaccurate and from random people. Ideally I think most people would like to use referral codes from their friends and have a single place they can rely on for finding a referral when they sign up for a service.

After taking a look at the app stores for iOS and Android, there was no existing product that had gained much traction and I wanted to see if I could make the most fully-featured, all around best referral app out there.

The second reason is that as a professional mobile developer, I wanted to gain more experience in product development, application design, and new mobile technologies. In terms of product development, I knew I wanted to make something larger in scope than a small technical project like a tool-style app and really work in a space where I could experiment with a variety of user experience challenges.

A referral sharing app was a good fit, as it has a lot of interesting user flows to tackle like exploring and ranking referrals, managing a user's friends list, tracking referral uses and sending out celebratory notifications, and getting creative with a plant theme that hopefully comes across as fun and more enjoyable than a plain list of unsorted codes. On the technical side, having worked with React Native for a number of years I was looking to see how it stacked up against alternatives like Flutter and wanted to see if Google's take on cross-platform mobile development was ready for prime time development (more on this later).

## How I approached building the app

There's nothing I like more when building an app than being able to ideate and contribute cross-functionally on its execution ranging from its product goals, to its user experience, frontend architecture and backend systems. When I'm in touch with the complete lifecycle of application development, I feel more invested in its overall success and connecting the different pieces together is a much smoother process when there's a common understanding of how it all works.

That isn't to say that having everyone be cross-functional on a project is the way to go, and I'm the first to admit that there are a lot of folks out there with much more experience, success and better advice than I have, this is more just a reflection on what I did when building the app so far and how it has gone.

With that caveat out of the way, how I approached getting started followed this very simple model:

![Flow chart](/images/tech/pollyn-process.png)

I'll briefly break down how each of those steps went:

## What is the main goal of the product?

This one was pretty clear. I wanted it to be an easy, reliable and enjoyable way to share referral codes and let the people you care about use them when they need them.

## What features are needed to achieve this goal?

To solve this goal, I knew it would need support for friending people in the app, and therefore a logged-in experience. It would also need the basic lifecycle of adding, updating and removing referrals, as well as exploring and searching for the ones people had added.

As a non-designer, this was challenging, but also a lot of fun and satisfying to work out. Some first (and terrible looking) sketches for core features looked like this:

<div class="flex-container">
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-add-referral.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-collect-referral.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-explore.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-view-friend.png" height="500px" />
   </div>
</div>


Which after a number of iterations, currently look like this:

<div class="flex-container">
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-add-referral-current.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-collect-referral-current.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-explore-current.png" height="500px" />
   </div>
   <div class="flex-items">
        <img src="{{ site.baseurl }}/images/tech/pollyn-view-friend-current.png" height="500px" />
   </div>
</div>

I'm satisfied with how the product has developed so far for launch, but I'm sure that many talented folks who design products for a living could do it much better than I can and am welcoming feedback and collaboration.

## What technologies best enable those features?

Knowing that I wanted the app to be available on both iOS and Android and wanting to try something other than React Native, I started by looking into Flutter. Overall it needed to have robust cross-platform support. TLDR it does! It has largely been a delight to work with so far.

After building an initial prototype testing on Android, I opened it up on iOS and had **absolutely no** additional work fixing bugs or disparities between platforms besides the essentials like push notifications, purchases, and other native platform requirements. This is thanks to how Flutter renders its UIs and handles cross-platform elements which I plan to dive into more in a comparison post between React Native and Flutter.

For the backend, I had a couple requirements I was looking for:

1. **Low maintenance** - Having setup application servers using more manual services like DigitalOcean before, I wanted something that abstracted away a lot of the complexity of setting up and servicing servers myself so that I could focus on the experience.

2. **Built-in platform services** - It is a lot of work and risk building features like authentication, auto-scale, pub/sub, and other platform systems from the ground up. A service that bundles all of those core features together would save a lot of effort and really accelerate time to market.

3. **Realtime** - Having worked on a number of client apps where state management and data freshness can cause all kinds of developer complexity and headaches, a realtime system would make it easier and faster to build experiences and also make it feel more responsive for users.

I ended up choosing [Firebase](https://firebase.google.com/?gclid=Cj0KCQiA1pyCBhCtARIsAHaY_5csKdtHI-Pf0-tP1ff0IvbUC80yWYQQv-dNmMgwoHtbVaAwJVSbotQaAp2zEALw_wcB&gclsrc=aw.ds) because of it's robust platform services, reasonable pricing model, close integration with Flutter as another Google product, and support for realtime data management using [Cloud Firestore](https://firebase.google.com/docs/firestore).

I've had a lot of wins with Firebase and Cloud Firestore and I'm looking forward to doing a walkthrough on building applications using these products in the near future.

## What was the prioritization and MVP cutoff?

Prioritization started off pretty straightforwardly: first set up authentication, a user model, CRUD for referrals, and core native Android/iOS services like push notifications.

With those things out of the way, keeping track of features and priorities with a standard JIRA style board was helpful. I used GitHub's built-in board for the project repository to keep track of everything to do. 

![Ticket board](/images/tech/pollyn-board.png)

Figuring out the feature cutoff for the launch was somewhat challenging, While I had lots of ideas around what features I *could* build, from working on past projects I know that you need to really hear from users before you can accurately identify what features you *should* build.

I set a core feature cut-off point for the end of the year and distributed an alpha build to some friends in January to get some initial thoughts which was really helpful and I wish a big thanks to everyone who participated! From there I iterated on some feedback and added/removed some things to get it ready for this public launch.

## Launched 🚀

 The app is now available on [iOS](https://apps.apple.com/us/app/pollyn/id1544180016) and [Android](https://play.google.com/store/apps/details?id=com.pollyn.app) or via the [the website](https://www.pollyn.app).

It's been a great experience working on the project so far and I look forward to seeing where it goes from here. If you have product or design skills and have some free time to explore how it can be made better, don't hesitate to reach out to [dan@pollyn.app](mailto:dan@pollyn.app).


