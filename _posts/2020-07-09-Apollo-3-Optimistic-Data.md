---
layout: post
title: Deconstructing Apollo Part 2&#58; Optimistic Updates
image: '/images/tech/apollo-layers.jpg'
category: Tech
tags: [JavaScript, Apollo, GraphQL, Cache, Optimistic]
---

The ins-and-outs of Apollo optimistic mutations.

<!--halt-->

# [Optimistic updates](#optimistic-updates)

An email just came into your inbox, you go to check what it is and see that it's just some LinkedIn recruiter trying to get you interested in their series B company with X million in funding and a unique, disruptive take on an industry set to explode in the next couple years. Because you're a rockstar developer and get emails like this all the time, you swipe the email away and it moves to your archives. 

While the email disappeared immediately, it might be the case that it has not actually been marked as archived on any server, and is instead optimistically updating locally in your email application. This type of functionality is commonplace in apps to provide a fluid experience that isn't interrupted by lots of loading states.

The Apollo Client comes with support for optimistic updates which you can check out [on their docs](https://www.apollographql.com/docs/react/performance/optimistic-ui/). The official documentation does a great job of illustrating how to use this feature in your own applications, so I won't go into much detail on how to use it here. In summary it involves specifying an optimistic response for your mutations like this:

```typescript
const [
  archiveEmail,
  {
    data: archiveEmailData,
    loading: archiveEmailLoading,
    error: archiveEmailError,
  },
] = useMutation(archiveEmailQuery, {
  optimisticResponse: {
    __typename: "Mutation",
    archiveEmail: {
      __typename: "ArchiveEmailResponse",
      data: {...}
    },
  },
});
```

There are a variety of approaches libraries can take to supporting optimistic updating. Let's dive into how it's implemented in the Apollo 3 cache.

## [A tale of two data properties](#tale-of-two-data-properties)

Like most journeys into the inner workings of Apollo, we start at the client layer. As we've discussed before, the client maintains a reference to its internal data store called the EntityStore which holds cached queries.

```typescript
// InMemoryCache.ts
constructor(config: InMemoryCacheConfig = {}) {
  super();
  ...
  // Passing { resultCaching: false } in the InMemoryCache constructor options
  // will completely disable dependency tracking, which will improve memory
  // usage but worsen the performance of repeated reads.
  this.data = new EntityStore.Root({
    policies: this.policies,
    resultCaching: this.config.resultCaching,
  });
  ...
  // When no optimistic writes are currently active, cache.optimisticData ===
  // cache.data, so there are no additional layers on top of the actual data.
  // When an optimistic update happens, this.optimisticData will become a
  // linked list of OptimisticCacheLayer objects that terminates with the
  // original this.data cache object.
  this.optimisticData = this.data;
  ...
}
```

As we can see in the constructor, on instantiation the client spins up a new root EntityStore to store cached data referenced by `this.data`. It writes a second property called `optimisticData` which as described in the comment, is equal to the `data` EntityStore reference provided there is no ongoing optimistic mutation.

Let's fire our optimistic mutation from above and see how it's processed:

```typescript
const [
  archiveEmail,
  {
    data: archiveEmailData,
    loading: archiveEmailLoading,
    error: archiveEmailError,
  },
] = useMutation(archiveEmailQuery, {
  optimisticResponse: {
    __typename: "Mutation",
    archiveEmail: {
      __typename: "ArchiveEmailResponse",
      data: {...}
    },
  },
});
archiveEmail();
```

The first spot to callout in the Apollo code is in the `QueryManager`:

```typescript
if (optimisticResponse) {
  const optimistic = typeof optimisticResponse === 'function'
    ? optimisticResponse(variables)
    : optimisticResponse;

  this.cache.recordOptimisticTransaction(cache => {
    markMutationResult({
      mutationId: mutationId,
      result: { data: optimistic },
      document: mutation,
      variables: variables,
      queryUpdatersById: generateUpdateQueriesInfo(),
      update: updateWithProxyFn,
    }, cache);
  }, mutationId);
}
```

As it processes the mutation, if it includes an optimistic response then it will mark a mutation result with that optimitic data in order to eagerly write it into the cache, calling `cache.write()` for each mutation result:

```typescript
cache.performTransaction(c => {
  cacheWrites.forEach(write => c.write(write));

  // If the mutation has some writes associated with it then we need to
  // apply those writes to the store by running this reducer again with a
  // write action.
  const { update } = mutation;
  if (update) {
    tryFunctionOrLogError(() => update(c, mutation.result));
  }
});
```

We can see that it wraps these writes in a transaction. The Apollo cache uses a linked-list of optimistic data layers to support multiple ongoing optimistic mutations. Like layers of an onion, it segments the different changes to the cache applied by each mutation so that they can later easily be removed when the result from the server returns.

The transaction API creates a new layer for our optimistic mutation:

```typescript
public performTransaction(
    transaction: (cache: InMemoryCache) => any,
    // This parameter is not part of the performTransaction signature inherited
    // from the ApolloCache abstract class, but it's useful because it saves us
    // from duplicating this implementation in recordOptimisticTransaction.
    optimisticId?: string
  ) {
    const perform = (layer?: EntityStore) => {
      const { data, optimisticData } = this;
      ++this.txCount;
      if (layer) {
        this.data = this.optimisticData = layer;
      }
      try {
        transaction(this);
      } finally {
        --this.txCount;
        this.data = data;
        this.optimisticData = optimisticData;
      }
    };

    if (typeof optimisticId === "string") {
      // Note that there can be multiple layers with the same optimisticId.
      // When removeOptimistic(id) is called for that id, all matching layers
      // will be removed, and the remaining layers will be reapplied.
      this.optimisticData = this.optimisticData.addLayer(optimisticId, perform);
    } else {
      // If we don't have an optimisticId, perform the transaction anyway. Note
      // that this.optimisticData.addLayer calls perform, too.
      perform();
    }

    // This broadcast does nothing if this.txCount > 0.
    this.broadcastWatches();
  }
```

If the transaction executed is an optimistic one, identified by the presence of an `optimisticId`, then the transaction API will update the cache's `optimisticData` reference to a new layer. `EntityStore.addLayer` creates a new `Layer` instance which as part of its construction, calls the passed transaction `perform` function:

```typescript
class Layer extends EntityStore {
  constructor(
    public readonly id: string,
    public readonly parent: EntityStore,
    public readonly replay: (layer: EntityStore) => any,
    public readonly group: CacheGroup
  ) {
    super(parent.policies, group);
    replay(this);
  }

  public addLayer(
    layerId: string,
    replay: (layer: EntityStore) => any
  ): EntityStore {
    return new Layer(layerId, this, replay, this.group);
  }
  ...
}
```

As we can see, each new layer is another instance of the EntityStore. When the `perform` is executed as part of the optimistic transaction, it will receive the newly created layer and set the cache's `data` and `optimisticData` references to the new layer for the duration of the transaction. This allows all subsequent writes and side-effects triggered by this transaction to be isolated to the new EntityStore layer.

If these data updates weren't isolated to their own layer and had been merged into the rest of the cache's data, then when the optimistic mutation's result returns from the server, it would be difficult and likely impossible to undo the temporary optimistic response since it has been merged in and altered by other writes.

After the perform function runs the transaction, it resets the the cache's `data` reference so that future writes are once again applied to the root layer.

While the `data` reference is restored, the cache's `optimisticData` reference is instead updated to the new layer returned by `addLayer`:

```typescript
  this.optimisticData = this.optimisticData.addLayer(optimisticId, perform);
```

## [Reading from the optimistic layer](#reading-from-optimistic-layer)

Now that our optimistic response has been layered onto the cache's data store, reads need to be directed to check that optimistic layer. Queries watching for changes to the cache access its data using a `readCache` function calling `cache.diff` to see if there are changes it cares about:

```typescript
const readCache = () => this.cache.diff<any>({
  query,
  variables,
  returnPartialData: true,
  optimistic: true,
});
```

It by default passes `optimistic` as `true`, which will tell the cache to try and read that data from the its `optimisticData` reference containing our layered response:

```typescript
public diff<T>(options: Cache.DiffOptions): Cache.DiffResult<T> {
  return this.storeReader.diffQueryAgainstStore({
    store: options.optimistic ? this.optimisticData : this.data,
    rootId: options.id || "ROOT_QUERY",
    query: options.query,
    variables: options.variables,
    returnPartialData: options.returnPartialData,
    config: this.config,
  });
}
```

`cache.diff` will use the `EntityStore.get` API to access the data it needs. If that data doesn't exist on the current layer, it will use the layer's reference to its parent to traverse the list up to the previous EntityStore instance, in our simple case, the immediate parent of our optimistic layer would be the `EntityStore.Root` where it would find the remaining cached data:

```typescript
public get(dataId: string, fieldName: string): StoreValue {
  this.group.depend(dataId, fieldName);
  if (hasOwn.call(this.data, dataId)) {
    const storeObject = this.data[dataId];
    if (storeObject && hasOwn.call(storeObject, fieldName)) {
      return storeObject[fieldName];
    }
  }
  if (
    fieldName === "__typename" &&
    hasOwn.call(this.policies.rootTypenamesById, dataId)
  ) {
    return this.policies.rootTypenamesById[dataId];
  }
  if (this instanceof Layer) {
    return this.parent.get(dataId, fieldName);
  }
}
```

## [Peeling off the optimistic layer](#peeling-off-optimistic-layer)

The cache will continue to read from our optimistic layer for the duration that the mutation is waiting for a response from the server. Once the server response comes back, the `QueryManager` removes the optimistic layer:

```typescript
complete() {
  if (error) {
    self.mutationStore.markMutationError(mutationId, error);
  }

  if (optimisticResponse) {
    self.cache.removeOptimistic(mutationId);
  }

  self.broadcastQueries();

  if (error) {
    reject(error);
    return;
  }
  ...
}
```

Which calls `removeLayer` on the `optimisticData` reference:

```typescript
public removeOptimistic(idToRemove: string) {
  const newOptimisticData = this.optimisticData.removeLayer(idToRemove);
  if (newOptimisticData !== this.optimisticData) {
    this.optimisticData = newOptimisticData;
    this.broadcastWatches();
  }
}
```

The `removeLayer` function is a recursive API that walks up the linked list of layers from the last layer towards the root until it finds the one matching the mutation:

```typescript
public removeLayer(layerId: string): EntityStore {
  // Remove all instances of the given id, not just the first one.
  const parent = this.parent.removeLayer(layerId);

  if (layerId === this.id) {
    // Dirty every ID we're removing.
    if (this.group.caching) {
      Object.keys(this.data).forEach((dataId) => {
        // If this.data[dataId] contains nothing different from what
        // lies beneath, we can avoid dirtying this dataId and all of
        // its fields, and simply discard this Layer. The only reason we
        // call this.delete here is to dirty the removed fields.
        if (this.data[dataId] !== (parent as Layer).lookup(dataId)) {
          this.delete(dataId);
        }
      });
    }
    return parent;
  }

  // No changes are necessary if the parent chain remains identical.
  if (parent === this.parent) return this;

  // Recreate this layer on top of the new parent.
  return parent.addLayer(this.id, this.replay);
}
```

It deletes any data the optimistic layer introduced, and then returns its parent's layer, unwinding the callstack. If there was another child optimistic layer below the one that was removed, the grandparent layer will replay the child's transaction on top of itself to recreate the child layer. Let's consider an example of how this would work:

Suppose we have 5 outstanding optimistic mutations. The cache's `data` reference is still the root layer. The cache's `optimisticData` points to the 5th optimistic layer.


* `data` - Root layer
* `optimisticData` - Root <- Layer 1 <- Layer 2 <-  Layer 3 <- Layer 4 <- **Layer 5**

Now let's go through what happens when the mutation for optimistic layer 3 returns from the server first.

1. `removeLayer` is called on `this.optimisticData`.
2. `removeLayer` recursively walks up the list until it reaches Layer 3.
3. Layer 3 deletes its data and returns its parent reference, Layer 2.
4. Layer 4 receives its grandparent reference, Layer 2, from Layer 3 and calls `addLayer` on it, passing its own `replay` function which reapplies its optimistic data changes on top of Layer 2.
5. Layer 4 returns this new Layer 6, and is itself discarded.
6. Layer 5 receives Layer 6, and similarly replays itself on top, returning new Layer 7.
7. The `removeLayer` call stack finishes unwinding, returning to `Cache.removeOptimistic`, which sets its `optimisticData` reference to Layer 7.

The `optimisticData` chain now looks like this:

Root <- Layer 1 <- Layer 2  <- Layer 6 <- **Layer 7**

## [Why not re-use Layer 4 and 5?](#why-not-use-layer-4-5)

Layer 4 and 5 may have relied on data in removed Layer 4 for writes and side-effects executed in their own transactions which the removal of Layer 3 would not know how to undo. Instead, their current data is discarded, and their transactions are re-applied fresh now that Layer 3 has been removed.

For example, suppose that each layer is an optimistic mutation to archive a different one of those emails (we swipe really fast) and that as part of the optimistic transaction for archiving the current email, it references the user's adjacent archived email on its data layer so that the user can move between them.

If we just removed Layer 3, then we'd need to know how to update Layer 4's data to now reference a different email. Instead of having to include these complex data unwinders, it is easier to apply the same operation for archiving subsequent emails again.

## [Cache you later](#cache-you-later)

This has been a look at how Apollo incorporates optimistic mutations into its cache model. In part 3 we'll take a look at how data from the cache reaches React components through the `useQuery` hook.