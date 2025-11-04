---
title: "Slack-style search on Flutter Web"
layout: post
authors: ["Dan Reynolds"]
tags: ["Flutter", "Library", "Web"]
category: Tech
image: "/images/tech/paginated-search/image.jpg"
---

Get Slack-style desktop search modals on Flutter web with the PaginatedSearchBar library. 

<!--halt-->

> This x-post is originally available at the [Pollyn Engineering blog](https://blog.pollyn.app/posts/2021-11-10-paginated-search/){:target="_blank"}.

By combining some of the libraries we've discussed in the past like [Modal Stack Router](https://blog.pollyn.app/posts/2021-11-02-building-modal-flows/){:target="_blank"} for building modal flows on Flutter web and [Endless](https://blog.pollyn.app/posts/2021-11-09-endless-scroll-views/){:target="_blank"} for building infinite lists, we can build a Slack-style modal search bar that looks like this:

![Demo](/images/tech/paginated-search/demo.gif)

This widget is called [PaginatedSearchBar](https://pub.dev/packages/paginated_search_bar){:target="_blank"} and it supports extensive customization with custom styling, headers, placeholders, footers and more. Let's look at a coding example:

```dart
class ExampleItem {
  final String title;

  ExampleItem({
    required this.title,
  });
}

PaginatedSearchBar<ExampleItem>(
  onSearch: ({
    required pageIndex,
    required pageSize,
    required searchQuery,
  }) async {
    // Call your search API to return a list of items
    return [
      ExampleItem(title: 'Item 0'),
      ExampleItem(title: 'Item 1'),
    ];
  },
  itemBuilder: (
    context, {
    required item,
    required index,
  }) {
    return Text(item.title);
  },
);
```

In this basic usage, you only need to specify two options to get started. An `onSearch` function for fetching data and an `itemBuilder` for how it should be displayed in the search results list. If you need more functionality than that, like header and footer sections, you can pass some additional builders:

```dart
PaginatedSearchBar<ExampleItem>(
  maxHeight: 300,
  hintText: 'Search',
  headerBuilder: (context) {
    return const Text("I'm a header!");
  },
  headerBuilder: (context) {
    return const Text("I'm a footer!");
  },
  emptyBuilder: (context) {
    return const Text("I'm an empty state!");
  },
  onSearch: ({
    required pageIndex,
    required pageSize,
    required searchQuery,
  }) async {
    return [
      ExampleItem(title: 'Item 0'),
      ExampleItem(title: 'Item 1'),
    ];
  },
  itemBuilder: (
    context, {
    required item,
    required index,
  }) {
    return Text(item.title);
  },
);
```

![Advanced demo](/images/tech/paginated-search/advanced-demo.gif)

## State Properties

In the previous example, our search results list had a fixed header. What if we only wanted to show a header when the list is empty? `PaginatedSearchBar` builders use the [StateProperty](https://pub.dev/packages/state_property){:target="_blank"} pattern found in Flutter Material's core widgets such as [TextButton](https://api.flutter.dev/flutter/material/MaterialStateProperty-class.html){:target="_blank"} to support greater customization.

The Material UI libray uses this pattern to let consumers of core widgets like `TextButton` style it differently when it is in one more states like hover or pressed. The basic example from the docs looks like this:

```dart
TextButton(
  style: ButtonStyle(
    // Use the color green as the background color for all button states.
    backgroundColor: MaterialStateProperty.all<Color>(Colors.green),
  ),
);

TextButton(
  style: ButtonStyle(
    backgroundColor: MaterialStateProperty.resolveWith<Color>(
      // The state property passes all the current states the button is in
      // so that the button style can be customized.
      (Set<MaterialState> states) {
        // Lighten the button color when it is in the pressed state. 
        if (states.contains(MaterialState.pressed))
          return Theme.of(context).colorScheme.primary.withOpacity(0.5);
        return null;
      },
    ),
  ),
);
```

We use this same pattern to support customizing the search bar based on its current states. The possible states are defined below:

```dart
enum PaginatedSearchBarState {
  /// Present when the search bar is searching for items. Triggered when they update their search
  /// query in the input.
  searching,

  /// Present when the search bar is fetching a page of items either as a result of a modified search query
  /// or by scrolling to the bottom of the list view and triggering the next page load.
  loading,

  /// Present when the search bar has no matching items for the current search query.
  empty,

  /// Present when the search bar has no more items to fetch for the current search query. Triggered
  /// when the [PaginatedSearchBar.onSearch] function returns fewer than [PaginatedSearchBar.pageLimit]
  /// items or [EndlessPaginationDelegate.maxPage] has been reached and no more items can be fetched.
  done,

  /// Present the input is currently focused.
  focused,
}
```

In order to only show a header when the list is empty, we can use the `headerBuilderState` state property:

```dart
PaginatedSearchBar<ExampleItem>(
  maxHeight: 300,
  hintText: 'Search',
  headerBuilderState: PaginatedSearchBarBuilderStateProperty.empty((context) {
    return const Text("I'm a header that only shows when the results are empty!");
  }),
  emptyBuilder: (context) {
    return const Text("I'm an empty state!");
  },
  onSearch: ({
    required pageIndex,
    required pageSize,
    required searchQuery,
  }) async {
    return [
      ExampleItem(title: 'Item 0'),
      ExampleItem(title: 'Item 1'),
    ];
  },
  itemBuilder: (
    context, {
    required item,
    required index,
  }) {
    return Text(item.title);
  },
);
```

## Custom Styling

We can use the same state property pattern to support custom styling. Here's a search bar that changes its text color from red to green when it has data:

```dart
PaginatedSearchBar<ExampleItem>(
  maxHeight: 300,
  hintText: 'Search',
  inputStyleState:
      PaginatedSearchBarStyleStateProperty.resolveWith((states) {
    if (states.contains(PaginatedSearchBarState.empty)) {
      return TextStyle(color: Colors.red);
    }
    return TextStyle(color: Colors.green);
  }),
  placeholderBuilder: (context) {
    return const Text("I'm a placeholder state!");
  },
  onSearch: ({
    required pageIndex,
    required pageSize,
    required searchQuery,
  }) async {
    return [
      ExampleItem(title: 'Item 0'),
      ExampleItem(title: 'Item 1'),
    ];
  },
  itemBuilder: (
    context, {
    required item,
    required index,
  }) {
    return Text(item.title);
  },
);
```

![Style demo](/images/tech/paginated-search/style-demo.gif)


## How it works

Under the hood, the `PaginatedSearchBar` widget is basically just the following:

```dart
Column(
  children: [
    // Our search input
    TextFormField(...),
    AnimatedSize(
      child: EndlessPaginationListView(...),
    ),
  ]
);
```

The composability of Flutter widgets make it relatively straightforward to take our existing tools like our infinite list view and combine them with widgets like text fields to create helpful new elements like search bars. If you have feedback on features that would make `PaginatedSearchBar` more useful in your own applications then feel free to let us know at the project [GitHub](https://github.com/danReynolds/paginated_search_bar){:target="_blank"}. Happy coding!