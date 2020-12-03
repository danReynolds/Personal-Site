---
layout: post
title: Setting up Google Billing using Flutter and Firebase
image: '/images/tech/payment.jpg'
category: Tech
tags: [Flutter, Google, Billing]
---

Putting together the documentation to get working Billing setup.

<!--halt-->

## Billing + Flutter

1. Show the user what they can buy.
2. Launch the purchase flow for the user to accept the purchase.
3. Verify the purchase on your server.
4. Give content to the user, and acknowledge delivery of the content. Optionally, mark the item as consumed so that the user can buy the item again.

Let's see how we can implement these steps in a Flutter app:

## Show the user what they can buy.

We'll first want to follow the steps in the [Google in_app_purchase flutter SDK](https://github.com/flutter/plugins/blob/master/packages/in_app_purchase/example/README.md) to setup our app for in-app purchases. Assuming you've done the setup linked to in the `in_app_purchase` SDK's README, let's see how we use the SDK to make purchases.

First we'll want to query for the existing products we want to server to the user. These product IDs can be served from your backend or hard-coded depending on your app's needs.

```dart
import 'package:in_app_purchase/in_app_purchase.dart';

InAppPurchaseConnection.instance
  .queryProductDetails(productsIds)
  .then((data) async {
    // Store the returned ProductDetailsResponse for use later on
    _productsById = data.productDetails
        .fold({}, (acc, product) {
      acc[product.id] = product;
      return acc;
    });
}),
```

## Launch the purchase flow for the user to accept the purchase.

After getting our products, we can use them to make purchases:

```dart
InAppPurchaseConnection.instance.buyNonConsumable(
  purchaseParam: PurchaseParam(
    productDetails: _productsById['your_product_id'],
  ),
);
```

This will bring up the Google in-app purchase dialog, which if all setup in the play developer console, should look like this:

![Billing example](/images/tech/billing.png)

For this to work you need to go through a number of hoops in the play developer console. Making sure that you have an alpha track release of your app published and that your current user is whitelisted as a tester of the app. For me, it also took a few days before the app started showing up for the whitelisted testers in the play store after being approved on the alpha track.

Once they make the purchase, your app will need to listen for it's success asynchronously. I use the `in_app_purchase` library again here:

```dart
import 'package:in_app_purchase/in_app_purchase.dart';

InAppPurchaseConnection.instance.purchaseUpdatedStream.listen(
  (purchases) {
    purchases.forEach(
      (purchase) async {
        if (purchase.pendingCompletePurchase) {

          final billingClientPurchase = purchase.billingClientPurchase;
          final sku = billingClientPurchase.sku;
          final resp = await FirebaseFunctions.instance
              .httpsCallable('verifyPurchase')
              .call(
            {
              "sku": sku,
              "purchaseToken": billingClientPurchase.purchaseToken,
              "packageName": billingClientPurchase.packageName,
              "purchaseType": // either a subscription or oneTimePurchase, I check my SKUs to determine this
            },
          );

          if (resp.data['status'] == 200) {
            // Complete the purchase and show the content to the user
            await InAppPurchaseConnection.instance.completePurchase(purchase);
            showContent();
          }
        }
      }
    );
  }
);
```

The `purchaseUpdatedStream` from the `InAppPurchase` SDK will deliver the purchased item asynchronously after the user makes the purchase.

## Verify the purchase on your server.

We'll still want to verify the purchase on our server so that we can make sure the user has indeed actually made a purchase and check that they're not doing things lie is re-using an existing `purchaseToken` to double dip on our products.

For this, I use a cloud function:


```dart
import * as functions from 'firebase-functions';
import * as key from './google-service-account.json';
import { google } from 'googleapis';

enum PurchaseType {
  subscription = "subscription",
  oneTimePurchase = "oneTimePurchase"
}

const authClient = new google.auth.JWT({
  email: key.client_email,
  key: key.private_key,
  scopes: ["https://www.googleapis.com/auth/androidpublisher"]
});

const playDeveloperApiClient = google.androidpublisher({
  version: 'v3',
  auth: authClient
});
```

You will need to create a service account to be able to use the play developer APIs, which you can create under **Settings > Developer Account > API access** in the play console.

Now that we have instantiated the play developer API, we'll want to query for our purchase:


```dart
const { sku, purchaseToken, packageName, purchaseType } = data;
  const userId = context.auth?.uid!;

  try {
    await authClient.authorize();

    if (purchaseType === PurchaseType.subscription) {
      const subscription = await playDeveloperApiClient.purchases.subscriptions.get({
        packageName: packageName,
        subscriptionId: sku,
        token: purchaseToken
      });

      // Ensure payment has been received by checking payment state of any subscription trying to be verified
      // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions
      if (subscription.status === 200 && subscription?.data?.paymentState === 1) {
        // Return a success to the client and store the subscription in your server however necessary.
      }
    } else {
      const oneTimePurchase = await playDeveloperApiClient.purchases.products.get({
        packageName: packageName,
        productId: sku,
        token: purchaseToken
      });

      if (oneTimePurchase.status === 200 && oneTimePurchase.data.purchaseState === 0) {
        // Return a success to the client and store the purchase in your server however necessary.
      }
    }
  } catch (e) {
    // handle error
  }
```

Here I'm querying for either a new subscription purchase or one-time purchase using the play developer API for the given `sku`, `packageName` and `purchaseToken`. If it comes back successful and the state of the response indicates that it's been purchased (I use the paymentState for a sub and the purchaseState for a OTP), then we're clear to write it to our server and tell the client that they can serve the successful purchase UI to the user.

## Give content to the user, and acknowledge delivery of the content.

After the verification in our cloud function returns successfully, we'll want to complete the purchase and show the content to the user:

```dart
// Complete the purchase and show the content to the user
await InAppPurchaseConnection.instance.completePurchase(purchase);
showContent();
```

AS noted in the `completePurchase` API, failure to call this method within 3 days of the purchase being made will result in the purchase being refunded so don't forget to complete it.

If your app only makes one-time purchases, then you can call wrap it a wrap here. But if your app uses subscriptions, then we need to additionally handle the lifecycle of our user's subscriptions beyond first purchase.

## Reading Subscription Changes

As described in the new [billing features update](https://android-developers.googleblog.com/2020/06/new-features-to-acquire-and-retain-subscribers.html) and the [subscriptions documentation](https://developer.android.com/google/play/billing/subscriptions), there are multiple states a subscription can be in. According to the billing features update this year, managing subscription states for restoring a subscription and it going on hold are now mandatory for apps:

![Subscription mandatory handling](/images/tech/subscriptions.png)

Unfortunately, we've reached the limit of the usefulness of the `in_app_purchase` SDK here because these subscription changes could happen asynchronously when the user goes to cancel or resubscribe to their subscription in the play store or if they have a payments problem for example that puts their subscription on hold.

In order to handle these subscription changes, we'll use the [Real-time developer notifications](https://developer.android.com/google/play/billing/subscriptions) as recommended in the subscriptions documentation to keep our subscriptions in sync. I'd recommend reading through that documentation as well as [the Real-time notifications reference](https://developer.android.com/google/play/billing/rtdn-reference#sub).

To process these real-time notifications, we'll use [Google's Pub/Sub](https://cloud.google.com/pubsub/docs/overview) event bus to process the notifications from our subscription. We'll want to create a new `topic` as according to the `Pub/Sub` documentation and [Quick-start guide](https://cloud.google.com/pubsub/docs/quickstart-console). We then need to link our app's notifications to this `topic` in the play developer console under the specific app and then **Monetization Setup**.

You'll enter your `topic` name there so that your app knows to publish events to your `Pub/Sub` topic. 

Once you've connected your app to `Pub/Sub`, we can write another cloud function to process `Pub/Sub` events:

```dart
import * as functions from 'firebase-functions';
import * as key from './google-service-account.json';
import { google } from 'googleapis';

const authClient = new google.auth.JWT({
  email: key.client_email,
  key: key.private_key,
  scopes: ["https://www.googleapis.com/auth/androidpublisher"]
});

const playDeveloperApiClient = google.androidpublisher({
  version: 'v3',
  auth: authClient
});

// See docs on subscription notifications for understanding the notification types:
// https://developer.android.com/google/play/billing/rtdn-reference#sub
// https://developer.android.com/google/play/billing/subscriptions

enum SubscriptionNotificationTypes {
  SUBSCRIPTION_RECOVERED = 1, // A subscription was recovered from account hold.
  SUBSCRIPTION_RENEWED = 2, // An active subscription was renewed.
  SUBSCRIPTION_CANCELED = 3, // A subscription was either voluntarily or involuntarily canceled. For voluntary cancellation, sent when the user cancels.
  SUBSCRIPTION_PURCHASED = 4, // A new subscription was purchased.
  SUBSCRIPTION_ON_HOLD = 5, // A subscription has entered account hold (if enabled).
  SUBSCRIPTION_IN_GRACE_PERIOD = 6, // A subscription has entered grace period (if enabled).
  SUBSCRIPTION_RESTARTED = 7, // User has reactivated their subscription from Play > Account > Subscriptions (requires opt-in for subscription restoration).
  SUBSCRIPTION_PRICE_CHANGE_CONFIRMED = 8, // A subscription price change has successfully been confirmed by the user.
  SUBSCRIPTION_DEFERRED = 9, // A subscription's recurrence time has been extended.
  SUBSCRIPTION_PAUSED = 10, // A subscription has been paused.
  SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED = 11, // A subscription pause schedule has been changed.
  SUBSCRIPTION_REVOKED = 12, // A subscription has been revoked from the user before the expiration time.
  SUBSCRIPTION_EXPIRED = 13, // A subscription has expired.
}

const getSubscription = async (token: string, subscriptionId: string, packageName: string) => {
  await authClient.authorize();

  return playDeveloperApiClient.purchases.subscriptions.get({
    packageName,
    subscriptionId,
    token
  });
}

export default functions.pubsub.topic('YOUR_TOPIC_NAME').onPublish(async (message) => {
  const messageBody = message.data ? JSON.parse(Buffer.from(message.data, 'base64').toString()) : null;

  if (messageBody) {
    const { subscriptionNotification, packageName } = messageBody;

    if (subscriptionNotification) {
      const { notificationType, purchaseToken, subscriptionId } = subscriptionNotification;

      switch(notificationType) {
        case SubscriptionNotificationTypes.SUBSCRIPTION_RECOVERED:
        case SubscriptionNotificationTypes.SUBSCRIPTION_RESTARTED:
        case SubscriptionNotificationTypes.SUBSCRIPTION_RENEWED: {
          const subscription = await getSubscription(purchaseToken, subscriptionId, packageName);
          // Write updated subscription to backend
          break;
        }
        case SubscriptionNotificationTypes.SUBSCRIPTION_REVOKED:
        case SubscriptionNotificationTypes.SUBSCRIPTION_EXPIRED: {
          // Write updated subscription to backend
          break;
        }
        case SubscriptionNotificationTypes.SUBSCRIPTION_CANCELED: {
          const subscription = await getSubscription(purchaseToken, subscriptionId, packageName);

          const expiresAt = subscription?.data.expiryTimeMillis;

          if (!expiresAt) {
            console.log(`Canceled subscription returned a null expiration time: ${purchaseToken} ${subscription.data}`);
            return;
          }
          
          const expiresAtTimestamp = admin.firestore.Timestamp.fromMillis(Number(expiresAt));

          // According to the cancellation API: https://developer.android.com/google/play/billing/subscriptions#cancel
          // If the expiration time when receiving a cancellation event is less than the current time, then just consider it expired
          if (Number(expiresAt) < Date.now()) {
          // Write updated subscription to backend

          // Otherwise, cancellation is considered separate from expiration as the user is entitled to the features granted by the subscription
          // until it expires.
          } else {
            // Write updated subscription to backend
          }
          break;
        }
        case SubscriptionNotificationTypes.SUBSCRIPTION_ON_HOLD: {
          // Write updated subscription to backend
          break;
        }
        case SubscriptionNotificationTypes.SUBSCRIPTION_IN_GRACE_PERIOD: {
          // Write updated subscription to backend
          break;
        }
        default:
          break;
      }
    }
  }
});
```

As we can see, we'll want to breakdown the notification by subscription notification type and then make changes to our status of the subscription as necessary. Your app may differ here in the events it cares about, mine for example only has annual subscriptions which cannot be paused, but your app may need to handle `SUBSCRIPTION_PAUSED` events as well.

## Canceling and Changing subscriptions

We've made sure that our subscription data is up to date when they change, but what about letting the user invoke changes from within the app? It's good practice to let users view, cancel and change their subscription in our applications.

For this, I recommend building a UI in your app for viewing a user's subscription, in my case it's their membership, and linking out to `https://play.google.com/store/account/subscriptions?sku=SKU_ID&package=YOUR_PACKAGE_NAME` as described in [the subscription documentation](https://developer.android.com/google/play/billing/subscriptions).

For changing subscriptions, you can let the user go through the purchase flow as we did earlier, but make sure that your verification cloud function checks for existing subscriptions and calls:

```dart
playDeveloperApiClient.purchases.subscriptions.cancel({
  packageName: packageName,
  subscriptionId: membership.id,
  token: membership.purchaseToken,
});
```

on the old one so that they don't have two running subscriptions. The play docs describe how you can [prorate subscription changes](https://developer.android.com/google/play/billing/subscriptions#change) but I have yet to figure out how to use that in Flutter since it is described only using the raw Android Kotlin/Java code:

```kotlin
// Retrieve a value for "skuDetails" by calling querySkuDetailsAsync()
val flowParams = BillingFlowParams.newBuilder()
        .setOldSku(previousSku, purchaseTokenOfOriginalSubscription)
        .setReplaceSkusProrationMode(desiredProrationMode)
        .setSkuDetails(upgradeOrDowngradeSkuDetails)
        .build();
val responseCode = billingClient.launchBillingFlow(activity, flowParams)
```

and I don't see these options exposed on the Flutter `in_app_purchase` SDK. For now I am just cancelling the old one and letting them subscribe to the new one. If that's egregiously wrong please let me know if I missed something and how I can use the proration model when changing subscriptions.

## Happy Billing

That's my my lightning guide on setting up Android billing in a Flutter app. I'll be setting up iOS billing in the near future and will expand on this guide with some more detailed steps on both platforms in the future. If you're stuck, feel free to reach out to me on [Twitter](https://twitter.com/TheDerivative) or at [my email](mailto:me@danreynolds.ca) and we can chat!

