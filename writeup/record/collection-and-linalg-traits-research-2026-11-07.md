# Collection and linear-algebra traits in Rust, Swift and Mojo

> **Research of its date.** This page records what the research found on 2026-11-07. Its findings about Rust, Swift and Mojo are facts of that date, with the versions named below. Its suggestions are not decisions. The design is in [`../reference/traits.md`](../reference/traits.md) §10 ([BaseTraits](../reference/traits.md#101-basetraits)); a suggestion taken up goes there, through the decision log or an open issue.

Research of 2026-11-07. The user asked for it: "When it comes to Base Traits and Lin Alg Traits, send out an agent that collects prior art from Rust, Swift, Mojo". One research agent read primary sources:
- **Rust:** RFCs, the std docs, the docs and changelogs of num-traits, alga, simba, nalgebra, ndarray, ndarray-linalg and faer, internals and users forum threads.
- **Swift:** the standard library's source (its doc comments), Swift Evolution proposals, the swift-evolution list and forums, Swift Numerics, Apple's Accelerate docs, the Swift for TensorFlow repositories.
- **Mojo:** the standard library docs (version 1.2.0), the release notes in modular/modular, the Modular forum, the MAX kernels' source.

Versions read: num-traits 0.2.19, alga 0.9.3, simba 0.10.2, nalgebra 0.35.0, ndarray 0.17.2, ndarray-linalg 0.18.1, faer 0.24.4 (faer-traits 0.24.0), Mojo std 1.2.0.

Every link below was opened. Claims marked *(uncertain)* rest on a secondary source or could not be checked. The earlier research on these languages, on other questions, is [`other-languages-research-2026-10-16.md`](other-languages-research-2026-10-16.md); this page does not repeat it.

## In brief

**Collections.**
- **Neither Rust's nor Swift's standard library has a trait for maps, and Rust's has no `Collection` trait either.** Rust removed its collection traits before 1.0, and every later attempt stalled. Swift has a protocol hierarchy for sequences and collections, but `Dictionary` is a struct with no protocol of its own. Mojo has neither. `Keyed{K, V}` has the least prior art of any row in our table.
- **All three separate single-pass from repeatable iteration.** Rust: `Iterator` against `IntoIterator` on `&C`. Swift: `Sequence` against `Collection`. Mojo: `Iterator` against `Iterable` (borrows) and `IterableOwned` (consumes). Our `Iterable{T}` does not say which it promises.
- **All three keep a size hint apart from an exact length, and none trusts either for memory safety.** Rust's `ExactSizeIterator` is a safe trait that unsafe code "must not rely on"; Mojo's `bounds()` are "hints only".
- **Growing a collection always takes values.** Rust's `resize(n, value)`, Mojo's `resize(length, fill)`; Swift has no resize at all. Uninitialized growth is marked unsafe in both. Our `Resizable` is `resize!(c, n)`, which grows a `Vector` with undefined elements.
- **Swift's index model is abstract and its slices keep their base's indices.** Swift warns to use `startIndex`, never `0`. Our `Indexable{T}` takes `c[i::Int]`, and its members include every `AbstractVector`, offset axes included.
- **Mojo removed fourteen named compound traits for composition with `&`**, and four comparison traits because a type almost never has one without the others. This supports `All{…}` and bundles as aliases.
- **Mojo moved from conformances checked late to conditional conformances** "to enforce trait requirements at compile time".

**Linear algebra and numerics.**
- **Rust's faer has a matrix-free operator trait:** `LinOp<T>` with `apply(out, rhs, par, stack)`, a scratch-size query, `conj_apply`; `BiLinOp` adds transpose and adjoint; `Precond` adds in-place application. Swift and Mojo have none.
- **Every solver trait found makes the in-place solve the required core, includes transposed and adjoint solves, and accepts views of any storage.** faer's `SolveCore<T>`, ndarray-linalg's `Solve<A>`. Our `Solvable{T}` takes `Vector{T}` only and has no transposed solve.
- **Fine-grained algebra was replaced by coarse traits.** nalgebra dropped alga's hierarchy (magma to field) for simba's, "simpler" and fit for SIMD. Swift split `AdditiveArithmetic` out of `Numeric` because "Vector spaces are not rings". Its differentiable types need only `AdditiveArithmetic`; the vector-space protocol of Swift for TensorFlow was not taken into Swift.
- **Storage traits are unsafe promises.** nalgebra's `RawStorage` and ndarray's `RawData` are `unsafe trait`s. ndarray 0.17 replaced functions generic over storage, "verbose and often hard to read", with one reference type. Mojo moved its kernels from a concrete layout to a layout trait (`TileTensor`).
- **Where the scalar is a parameter of the operator trait, mixed precision stays open.** faer's `LinOp<T>` and `SolveCore<T>` take it as a trait parameter. Mojo's kernels take one element type per operand plus an accumulator type.

## 1. The collection hierarchy

### 1.1 At a glance

| Concept | Rust std | Swift stdlib | Mojo std | BaseTraits |
|---|---|---|---|---|
| One pass | `Iterator` (`Item`) | `Sequence` (may be single-pass), `IteratorProtocol` | `Iterator` (`Element`) | `Iterable{T}` |
| Repeatable iteration | `IntoIterator` on `&C` | `Collection` | `Iterable` (borrows), `IterableOwned` (consumes) | not distinguished |
| Exact length | `ExactSizeIterator` on iterators; `len` is inherent on collections | `Collection.count`, O(n) unless random access | `Sized`, `SizedRaising` | `HasLength` |
| Size hint | `size_hint()` | `underestimatedCount` | `bounds()` | none (Julia: `Base.IteratorSize`) |
| Read by position | `Index<Idx>` (`Output`) | `Collection`'s subscript at `Index` | `__getitem__`; `Indexer` for index types | `Indexable{T}` |
| Write by position | `IndexMut<Idx>` | `MutableCollection` | `__setitem__` | `MutableIndexable{T}` |
| From both ends | `DoubleEndedIterator` | `BidirectionalCollection` | none found | none |
| Random access | slices, no trait | `RandomAccessCollection` | none found | implied by `Indexable` |
| Grow, shrink | `Extend<A>`, `FromIterator<A>`; inherent `resize`, `truncate` | `RangeReplaceableCollection` | inherent `resize`, `append` | `Resizable` |
| Keyed | none; maps implement `Index<&Q>` | none; `Dictionary` is a struct | none; `Dict` is a struct, `KeyElement` bounds its keys | `Keyed{K, V}` |
| Text | `Display` | `TextOutputStreamable`, `CustomStringConvertible` | `Writable` | `print`; `BoundedText` for a bound |

### 1.2 Rust

**The traits.**
- **`Iterator`** has one associated type, `Item`, one required method, `next`, and 75 provided methods in the current docs, unstable ones included ([`Iterator`](https://doc.rust-lang.org/std/iter/trait.Iterator.html)). Calling `next` after `None` "may or may not" resume, unless the iterator is fused.
- **`IntoIterator`** has `Item` and `IntoIter: Iterator<Item = Self::Item>`, and `for` loops use it ([`IntoIterator`](https://doc.rust-lang.org/std/iter/trait.IntoIterator.html)). `Vec<T>` implements it three times: by value, for `&Vec<T>` (items `&T`) and for `&mut Vec<T>` (items `&mut T`). Repeatable iteration is "iterate a borrow"; no trait promises it.
- **`ExactSizeIterator: Iterator`** provides `len`. It is "a safe trait and as such does _not_ and _cannot_ guarantee that the returned length is correct", so "`unsafe` code **must not** rely on" it ([`ExactSizeIterator`](https://doc.rust-lang.org/std/iter/trait.ExactSizeIterator.html)).
  - `TrustedLen` gives that guarantee. It is an `unsafe trait`, unstable ([`TrustedLen`](https://doc.rust-lang.org/std/iter/trait.TrustedLen.html)).
  - `Chain<A, B>` is not `ExactSizeIterator` even when both parts are: the sum may not fit in `usize`.
- **`size_hint`** returns a lower and an optional upper bound. It is "primarily intended to be used for optimizations such as reserving space" and "must not be trusted to e.g., omit bounds checks in unsafe code" ([`Iterator`](https://doc.rust-lang.org/std/iter/trait.Iterator.html)).
- **`DoubleEndedIterator: Iterator`** requires `next_back`; both ends "work on the same range, and do not cross" ([`DoubleEndedIterator`](https://doc.rust-lang.org/std/iter/trait.DoubleEndedIterator.html)).
- **`Index<Idx>`** has the index type as a trait parameter and `Output` as an associated type ([`Index`](https://doc.rust-lang.org/std/ops/trait.Index.html)).
  - `Vec<T>`, slices and `String` take any `I: SliceIndex`: `usize` or a range.
  - `HashMap<K, V>` takes `&Q` where `K: Borrow<Q>`, with `Output = V`.
  - The convention since RFC 235: `Index` panics on a bad index, and a collection with `Index` also offers `get`, which does not fail ([RFC 235](https://rust-lang.github.io/rfcs/0235-collections-conventions.html)).
- **`Extend<A>` and `FromIterator<A>`** take the item type as a trait parameter, so one type may accept several: `Vec<T>` is `Extend<T>` and `Extend<&T>`, `String` is `Extend<char>` and `Extend<&str>` ([`Extend`](https://doc.rust-lang.org/std/iter/trait.Extend.html), [`FromIterator`](https://doc.rust-lang.org/std/iter/trait.FromIterator.html)). `collect()` is the usual way to call `from_iter`.
- **Text:** `Display` has one method, `fmt(&self, f: &mut Formatter)`, and gives `ToString`. It says nothing of the output's length ([`Display`](https://doc.rust-lang.org/std/fmt/trait.Display.html)).

**Where the algorithms live.**
- On `Iterator`, as provided methods (`filter`, `fold`, `sum`, …); most require `Self: Sized`.
- On the collections, as inherent methods: `Vec::retain`, `Vec::resize`, `Vec::truncate` ([`Vec`](https://doc.rust-lang.org/std/vec/struct.Vec.html)). No trait states them.

**Why std has no `Collection` or `Map` trait.**
- **RFC 235 (2014) removed the traits it had** (`Collection`, `Mutable`, `MutableSeq`, `Deque`, `Map`, `MutableMap`, `Set`, `MutableSet`) ([RFC 235](https://rust-lang.github.io/rfcs/0235-collections-conventions.html)). Its reasons:
  - "Most important: the traits do not provide iterator methods like `iter`"; a full `Iterable` "requires HKT".
  - "The split between mutable and immutable traits is not well-motivated by any of the existing collections."
  - "Unlike inherent methods, which can easily be added and deprecated over time, a trait is 'forever'".
  - The plan: conventions for concrete collections now, traits "later on". It warned that experimental traits risk "becoming 'de facto' stable".
- **Gankra's "Collection Traits, Take 2" (2015-01-11)** drafted `Stack`, `Queue`, `Deque`, `Seq`, `Map`, `SortedMap`, `Set`, `SortedSet`, then a read/write split. The traits "can't really be expressed correctly because of iterator types and something something HKT"; sfackler: "These traits should probably not be added until HKT." ([internals](https://internals.rust-lang.org/t/collection-traits-take-2/1272))
- **Generic associated types** were proposed in 2016 for exactly this: "streaming iterators and collection traits", with an `Iterable` whose `Iter<'a>` borrows the collection ([RFC 1598](https://rust-lang.github.io/rfcs/1598-generic_associated_types.html)). They became stable in Rust 1.65, in November 2022, with `LendingIterator` as the example ([the stabilization post](https://blog.rust-lang.org/2022/10/28/gats-stabilization/)).
- **No collection traits followed.** The 2021 internals thread ([traits for common data structures](https://internals.rust-lang.org/t/traits-for-common-data-structures/14332)) found:
  - "arbitrary collections cease to be abstracted over usefully, as soon as you actually want to query";
  - `HashMap` needs `Hash` and `BTreeMap` needs `Ord`; `LinkedList` deliberately has no lookup by key;
  - agreement that ideal traits would be good, disagreement on what they should express;
  - lookup by a borrowed key needs `Borrow<Q>` with a higher-ranked bound.
- **The users forum, the same year:** "the signature of HashMap::get isn't object-safe, though, and has different bounds than BTreeMap::get"; such traits belong first "in a crate of collections traits"; "we don't even have a trait for numbers in std" ([users forum](https://users.rust-lang.org/t/newbe-does-rust-have-an-abstract-map-trait/69240)).

### 1.3 Swift

**The protocols.** Each is in the standard library's source, with its documentation.
- **`Sequence<Element>`** has `Element` and `Iterator: IteratorProtocol where Iterator.Element == Element`, and requires `makeIterator()` ([`Sequence.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Sequence.swift)).
  - It makes no promise that iteration is nondestructive: a second `for`-`in` over the same sequence has no defined behaviour. To promise it, "add conformance to the `Collection` protocol".
  - `underestimatedCount` is a nondestructive estimate that should not exceed the true count; the default is zero.
  - Two further requirements serve speed: `_customContainsEquatableElement` (a `Set` answers `contains` in constant time) and `withContiguousStorageIfAvailable` (returns `nil` without contiguous storage).
- **`Collection<Element>: Sequence`** is "guaranteed to be *multipass*" ([`Collection.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Collection.swift)).
  - Associated types: `Index: Comparable`; `SubSequence: Collection = Slice<Self>`; `Indices: Collection = DefaultIndices<Self>`; `Iterator = IndexingIterator<Self>`.
  - Required: `startIndex`, `endIndex`, `subscript(position:)`, `index(after:)`. `count` has a default and is O(n) unless the collection is a `RandomAccessCollection`.
  - "Saved indices may become invalid as a result of mutating operations."
- **`MutableCollection`** allows "changing the values of a collection's elements" "but not the length of the collection itself". "A value stored into a subscript of a `MutableCollection` instance must subsequently be accessible at that same position." ([`MutableCollection.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/MutableCollection.swift))
- **`RandomAccessCollection`** asks either `Strideable` indices or O(1) `index(_:offsetBy:)` and `distance(from:to:)`. With `Int`-strided indices it supplies the rest ([`RandomAccessCollection.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/RandomAccessCollection.swift)).
- **`RangeReplaceableCollection`** needs only `init()` and `replaceSubrange(_:with:)`; `append`, `insert`, `remove` and the rest default to those ([`RangeReplaceableCollection.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/RangeReplaceableCollection.swift)). `removeAll(where:)` is a requirement with defaults, and "The order of the remaining elements is preserved."
- **Text:** `TextOutputStreamable` writes to a `TextOutputStream`; `CustomStringConvertible` gives `description`; `LosslessStringConvertible` adds `init?(_ description:)` ([`OutputStream.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/OutputStream.swift)).
  - `print` tries `TextOutputStreamable`, then `CustomStringConvertible`, then `CustomDebugStringConvertible`, then reflection.
  - No requirement states or bounds the output's length.

**The index types.**
- `Collection.Index` is abstract. `Array`'s is `Int`, with `Indices = Range<Int>` ([`Array.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Array.swift)). `Dictionary`'s is an opaque struct ([`Dictionary.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Dictionary.swift)).
- **Slices keep their base's indices.** "The starting index for an `ArraySlice` instance isn't always zero." "Use `startIndex` and `endIndex` as the bounds for any element access, instead of `0` and `count`." ([`ArraySlice.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/ArraySlice.swift))

**`Dictionary`, and no map protocol.**
- `Dictionary<Key: Hashable, Value>` is a struct. It is a `Collection` of `(key: Key, value: Value)` with an opaque `Index` ([`Dictionary.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Dictionary.swift)).
- Its subscript by key returns `Value?`. `subscript(key:default:)` returns `Value`.
- **A `DictionaryProtocol` was asked for in swift-collections in 2023** and is still open ([issue 293](https://github.com/apple/swift-collections/issues/293)).
  - Its maintainer: "The protocol should ultimately live in the Standard Library, but we could prototype it within this package. (Transitioning it into the stdlib later is going to be painful, though.)"
  - It cannot refine `Collection`, because `OrderedDictionary` is not one.
  - Open questions: whether to split off a `MutableDictionaryProtocol` for read-only types; what mutation promises about indices; initializers that "none of" the dictionary types share.

**Where the algorithms live.**
- In protocol extensions. A method in an extension that is not a requirement is called directly: a member cannot replace it for generic callers.
- A **customization point** is a requirement with a default in an extension, so a member may replace it ([SE-0232](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0232-remove-customization-points.md)). It serves one of two reasons: different behaviour, or a faster implementation.
- "Customization points aren't free – they add a small cost at both compile time and run time." SE-0232 (Swift 5.0) removed four (`map`, `forEach`, `first`, `last`). Ben Cohen's pitch: "Once ABI stability has been declared for a framework, customization points can never be removed." ([pitch](https://forums.swift.org/t/pitch-remove-some-customization-points-from-the-std-lib-collection-protocols/16911))

**How its own types adopt them.** `Array` is `RandomAccessCollection, MutableCollection` and `RangeReplaceableCollection`, and `Equatable where Element: Equatable` ([`Array.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Array.swift)).

**Primary associated types.** SE-0358 (Swift 5.7) gave `Sequence`, `Collection` and its refinements `Element` as their primary associated type, and `SIMD` its `Scalar` ([SE-0358](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0358-primary-associated-types-in-stdlib.md)).
- Its advice: "Not every protocol needs primary associated types." "Limit yourself to just one primary associated type."
- `Numeric` got none: `Magnitude` is "too subtle and non-obvious".

### 1.4 Mojo

**The traits** (std 1.2.0).
- **`Iterator`** has the associated `comptime` member `Element` and requires `__next__(mut self) -> Self.Element`, which raises `StopIteration` at the end ([`Iterator`](https://mojolang.org/docs/std/iter/Iterator/)).
  - It provides `bounds() -> Tuple[Int, Optional[Int]]`, default `(0, None)`. "The bounds are hints only - iterators may not comply with them."
- **`Iterable`** requires `__iter__(ref self)`, which borrows the collection, so "the collection remains usable" afterwards ([`Iterable`](https://mojolang.org/docs/std/iter/Iterable/)). Its associated `IteratorType[iterable_mut, iterable_origin]` is parameterized by the borrow: the shape of RFC 1598's `Iterable`.
- **`IterableOwned`** consumes the collection ([iter module](https://mojolang.org/docs/std/iter/)). The algorithms there are free functions: `map`, `zip`, `enumerate`, `chain`, `peekable`.
- **`Sized`** requires `__len__(self) -> Int`. `SizedRaising` is for a length that may raise ([`Sized`](https://mojolang.org/docs/std/builtin/len/Sized/), [len module](https://mojolang.org/docs/std/builtin/len/)).
- **`Indexer`** marks the types an index may have: `__mlir_index__` converts to the machine index ([`Indexer`](https://mojolang.org/docs/std/builtin/int/Indexer/)).
- **Associated types** are declared in a trait with `associatedtype`, "most commonly used in collections" ([traits manual](https://mojolang.org/docs/manual/traits)).
- **Composition:** `T: A & B`. A named composition, `comptime SensorLike = DeflectionSensing & Loggable`, "isn't a new trait".

**The collections** are structs with no collection trait of their own ([collections](https://mojolang.org/docs/std/collections/)).
- **`List[T: AnyType]`** is `Sized`, `Iterable`, `Boolable`, …, and `Copyable`, `Equatable`, `Hashable`, `Writable` each where `T` is ([`List`](https://mojolang.org/docs/std/collections/list/List/)).
  - `__getitem__(idx: Int)` treats a negative index as out of bounds; a slice without a stride returns a `Span`.
  - `resize(length, fill: T)` pads with `fill`. `resize(unsafe_uninit_length=)` leaves new elements uninitialized.
- **`Dict[K: KeyElement, V: Movable]`** ([`Dict`](https://mojolang.org/docs/std/collections/dict/Dict/)):
  - `__getitem__` raises `DictKeyError`;
  - `get(key) -> Optional[V]` and `get(key, default) -> V`;
  - `__iter__` yields keys, as Python's does.
- **Text:** `Writable` provides `write_to(writer)` and `write_repr_to(writer)`, both with defaults by reflection. No method gives a size ([`Writable`](https://mojolang.org/docs/std/format/Writable/)).

## 2. Revisions and regrets

### 2.1 Swift

- **SE-0065, the index model (Swift 3.0).** Indices stopped advancing themselves (`i.successor()`); the collection advances them (`c.index(after: i)`) ([SE-0065](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0065-collections-move-indices.md)). The reasons:
  - for collections without random access, an index otherwise had to store "a reference to the collection's structure";
  - so code that handles indices "has to perform atomic reference counting";
  - "A live index makes underlying storage non-uniquely referenced, forcing unnecessary copies when the collection is mutated."
- **SE-0191 removed `IndexDistance` (Swift 4.1).** Distances between indices could be any `SignedInteger`, so generic code needed `numericCast`, and "these `numericCasts` are hard to use correctly" ([SE-0191](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0191-eliminate-indexdistance.md)).
  - The cases that used the generality were "very niche": "there are no such types in the Swift source compatibility suite". It became `Int`.
- **SE-0234 removed `SubSequence` from `Sequence` (Swift 5.0).** A sequence's default `SubSequence` was a type-erased `AnySequence`, and "type-erased wrappers are an optimization barrier" ([SE-0234](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0234-remove-sequence-subsequence.md)).
  - It also blocked conditional conformance from `Sequence` to `Collection`.
  - `SubSequence` now begins at `Collection`. `dropFirst`, `prefix` and the like on a `Sequence` return concrete types.
- **The multi-pass question (2016), not resolved.** Dave Abrahams: "Multi-pass-ness *is* the fundamental distinction between Sequence and Collection." ([swift-evolution, 2016-06-22](https://lists.swift.org/pipermail/swift-evolution/Week-of-Mon-20160620/021781.html))
  - The harm he named: users "don't recognize that there's a semantic restriction (assume you can make only a single-pass!)" on `Sequence`, and test with arrays and ranges, which are multi-pass ([forum, 2016-06-27](https://forums.swift.org/t/pitch-remove-destructive-consumption-from-sequence/3151/2)).
  - The other side, quoted there: "You currently have to over-constrain types to `Collection` even if you don't need to do so".
  - The current `Sequence` documentation keeps the single-pass permission ([`Sequence.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Sequence.swift)).
- **Customization points cut before ABI stability:** SE-0232 (§1.3).
- **A map protocol was never added** (§1.3).

### 2.2 Rust

- **The collection traits removed before 1.0, and not replaced** (§1.2): first for want of higher-kinded types, then for want of agreement on what to express. Generic associated types took six and a half years ([earlier research §8](other-languages-research-2026-10-16.md#8-the-complexity-budget)) and did not bring them back.
- **The lending iterator** (`LendingIterator`, an item that borrows from the iterator) needed generic associated types. At stabilization they had known limits: a higher-ranked bound on `I::Item<'a>` implies `'static`; traits with generic associated types are not object safe; a `Filter` over a lending iterator meets a borrow-checker error ([stabilization post](https://blog.rust-lang.org/2022/10/28/gats-stabilization/)).
- **A length that can be trusted** is a separate, unsafe and still unstable trait, `TrustedLen` (§1.2).

### 2.3 Mojo

Mojo's collection traits changed in nearly every release from 24.4 to 1.1 (the release notes of [24.4](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.24.4.md), [25.3](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.25.3.md), [25.4](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.25.4.md), [25.5](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.25.5.md), [25.6](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.25.6.md), [25.7](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.25.7.md), [26.1](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.26.1.md), [26.2](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v0.26.2.md), [1.0](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v1.0.0.md), [1.1](https://raw.githubusercontent.com/modular/modular/main/Mojo/docs/site/releases/v1.1.0.md)).

- **Iterators.**
  - 25.5 added `Iterator`, with `__has_next__()` and `__next__()`, and no form for iterating borrowed references.
  - 25.6 added `Iterable` and the defaulted `bounds()`.
  - A review of the abstraction (Owen Hilyard, 2025-09-19) found that `__has_next__` "may lead to a lot of duplicated checking or buffering inside of iterators" and "is a race condition without buffering" for queues ([forum](https://forum.modular.com/t/reviewing-the-iterator-iterable-abstraction/2288)). Chris Lattner answered that a raise as the stop signal, tied to the allocating `Error` type, "is not going to be very efficient", and pointed to typed raises.
  - 26.1 removed `__has_next__()`: `__next__()` raises `StopIteration`, following Python, "easier to implement", possibly "a minor performance win". `__next__` may return a value or a reference.
  - 25.7 made `Optional` an `Iterable` and an `Iterator`; 1.0 made it only an `Iterable` "of 0 or 1 elements".
  - 1.0 relaxed `IterableOwned` on the collections to `Movable & Deinitable` elements, for consuming loops over elements that cannot be copied.
- **Compound traits.** 25.3 added composition with `&` and removed fourteen named compound traits "in favor of trait composition": `WritableCollectionElement`, `ComparableCollectionElement`, `StringableCollectionElement` and eleven more. 25.4 removed `CollectionElement`: write `Copyable & Movable`.
- **Granularity.** 25.7 removed `LessThanComparable`, `GreaterThanComparable` and the two other one-operator traits for `Comparable`: it is "extremely rare that a type would only implement one of these".
- **Conformance.** Implicit (structural) conformance was deprecated in 25.4 and removed in 25.5 ([earlier research §1](other-languages-research-2026-10-16.md#1-conformance-declared-or-structural)).
- **Conditional conformance.**
  - 26.1 let `List`, `Dict`, `Set` and others conform to `Writable`, `Stringable` and `Representable` whatever their elements, with "late" checking of the element type at use ("unconditional conformances").
  - 26.2 replaced that with conditional conformances by `where` clauses, "to enforce trait requirements at compile time". `List` is `Equatable`, `Hashable` and `Writable` only where its element is.
  - 1.1 made `mojo doc` show the condition: the old output had made a conditional conformance "indistinguishable from an unconditional one".
- **Indexing.** 24.4 added `Indexer`: "Most standard library containers can now be indexed by any type that implements `Indexer`." The same release took `SIMD` out of it; std 1.2.0 lists `SIMD` as an `Indexer` again ([`SIMD`](https://mojolang.org/docs/std/simd/SIMD/)). 26.2 took `Bool` out: "Use `Int(my_bool)`".
- **Length.** 24.4 removed `Slice`'s `Sized`: a slice's length depends on the object it slices.
- **Text.** 26.2 deprecated `Stringable` and `Representable` for `Writable`, one writer-based trait with defaults. 26.1 had moved `Writer` and `Writable` to a `format` module, as tied to formatting rather than binary I/O.
- **Equality on vectors.** 25.6 made `==` on `SIMD` return one `Bool` instead of a mask, so `SIMD` could be `EqualityComparable` and serve "in sets, as dictionary keys, and in generic search algorithms". Elementwise comparison is `eq`, `lt` and the like ([`SIMD`](https://mojolang.org/docs/std/simd/SIMD/)).

## 3. Linear algebra and numerics

### 3.1 The numeric traits

**Rust.**
- **std has arithmetic operator traits and no numeric trait.** `Add<Rhs = Self>` has an associated `Output`; `SystemTime` is `Add<Duration>` ([`Add`](https://doc.rust-lang.org/std/ops/trait.Add.html)).
- **num-traits** has `Zero`, `One`, `Num`, `NumOps`, `NumRef`, `Float`, `Real`, `Signed`, `Bounded`, `NumCast`, `FromPrimitive`, `PrimInt` and some forty operator traits ([num-traits](https://docs.rs/num-traits/latest/num_traits/)). `Num` is `PartialEq + Zero + One + NumOps` and requires `from_str_radix`, parsing from a string ([`Num`](https://docs.rs/num-traits/latest/num_traits/trait.Num.html)).
- **alga** modelled abstract algebra ([`alga::general`](https://docs.rs/alga/latest/alga/general/index.html), [`alga::linear`](https://docs.rs/alga/latest/alga/linear/index.html)).
  - `AbstractMagma` to `AbstractField`, with `Additive` and `Multiplicative` operator types, and aliases such as `AdditiveGroup`.
  - 22 linear-algebra traits, from `VectorSpace` to `Isometry`. `VectorSpace: Module<Ring = Self::Field>` has the field as an associated type ([`VectorSpace`](https://docs.rs/alga/latest/alga/linear/trait.VectorSpace.html)).
- **nalgebra 0.21 replaced alga with simba.** Its changelog: the simba traits "are both simpler, and allow for significant optimizations like AoSoA SIMD" ([nalgebra changelog](https://docs.rs/crate/nalgebra/0.24.1/source/CHANGELOG.md)). alga's implementations stayed behind a feature flag.
- **simba's traits are generic in the number of SIMD lanes**: `Vector3<f32>` and `Vector3<f32x4>` share one normalization ([simba](https://docs.rs/simba/latest/simba/)).
  - `ComplexField` has an associated `RealField` and 55 methods, from `modulus` to `sinhc` ([`ComplexField`](https://docs.rs/simba/latest/simba/scalar/trait.ComplexField.html)).
- **ndarray's `LinalgScalar`** has no methods: "Elements that support linear algebra operations", `'static + Copy + Zero + One + Add + Sub + Mul + Div`, with a blanket implementation ([`LinalgScalar`](https://docs.rs/ndarray/latest/ndarray/trait.LinalgScalar.html)). Its `'static` bound serves "type-based specialization".
- **faer** had an `unsafe trait Entity` in 0.20, which split a scalar into components stored "in a separate container", with eleven associated types, most of them generic ([`Entity`](https://docs.rs/faer-entity/0.20.1/faer_entity/trait.Entity.html)). faer-traits 0.24 has `ComplexField`, `RealField`, `Conjugate` and no `Entity` ([faer-traits](https://docs.rs/faer-traits/latest/faer_traits/)).

**Swift.**
- **The tower:**
  - `AdditiveArithmetic` (`zero`, `+`, `-`) under `Numeric` (`*`, integer literals, an associated `Magnitude`);
  - then `SignedNumeric`;
  - then `BinaryInteger` and `FixedWidthInteger` ([SE-0104](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0104-improved-integers.md)) and `FloatingPoint` and `BinaryFloatingPoint` ([SE-0067](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0067-floating-point-protocols.md)).
- **SE-0233 (Swift 5.0) split `AdditiveArithmetic` out of `Numeric`:** "Vector spaces are not rings. Multiplication is not defined between vectors." ([SE-0233](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0233-additive-arithmetic-protocol.md)) `Numeric`'s literal requirement was also undefined for vectors of dynamic shape.
- **Swift Numerics:** `ElementaryFunctions` refines `AdditiveArithmetic`; `RealFunctions` adds what is hard to define beyond the reals; `Real` is "a floating-point type equipped with the full set of basic math functions" ([RealModule](https://raw.githubusercontent.com/apple/swift-numerics/main/Sources/RealModule/README.md)).
  - `AlgebraicField` adds `/` and `reciprocal`, for code "generic over real and complex types".
  - SE-0246 accepted these for the standard library, but "because of limitations in the compiler, the API could not be added to the standard library in a source-stable manner", so they live in a package.
- **SIMD (SE-0229, Swift 5.0):** `SIMDStorage` (`Scalar`), `SIMDScalar`, `SIMD`; widths are types (`SIMD2` to `SIMD64`) ([SE-0229](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0229-simd.md)).
  - Comparisons that act per lane are spelled `.==`, `.<` and return a mask; `==` is whole-value equality.
  - No matrices.
- **Swift for TensorFlow** was "an experiment" and "was archived in February 2021" ([tensorflow/swift](https://github.com/tensorflow/swift)).
  - Its `VectorProtocol: AdditiveArithmetic` had `associatedtype VectorSpaceScalar = Float` and paired `scaled(by:)` with a mutating `scale(by:)` ([swift-apis](https://raw.githubusercontent.com/tensorflow/swift-apis/main/Sources/TensorFlow/Core/VectorProtocol.swift)).
  - The differentiable programming that went into Swift asks of `TangentVector` only `Differentiable & AdditiveArithmetic`: differentiable types "should not be required to be a vector space" ([manifesto](https://raw.githubusercontent.com/swiftlang/swift/main/docs/DifferentiableProgramming.md)).
  - SE-0233 was one of four proposals the project took into Swift.

**Mojo.**
- **No numeric tower.** Numbers are `SIMD[dtype: DType, length]`; a scalar is a vector of one lane ([`SIMD`](https://mojolang.org/docs/std/simd/SIMD/)). `DType` "behaves like an enum", passed as a compile-time value with queries such as `is_floating_point()` ([`DType`](https://mojolang.org/docs/std/builtin/dtype/DType/)).
- 1.0 made `Int` an alias for `Scalar[DType.int]`.
- **Math is generic over the dtype, not bounded by a trait:** `sqrt[dtype: DType, width](x: SIMD[dtype, width])` ([`sqrt`](https://mojolang.org/docs/std/math/math/sqrt/)).
- **One trait per operation:** `Absable`, `Ceilable`, `Floorable`, `Powable`, `Roundable`, `Truncable`, `DivModable` ([math](https://mojolang.org/docs/std/math/math/)). `Powable` requires `__pow__(self, exp: Self) -> Self` ([`Powable`](https://mojolang.org/docs/std/math/math/Powable/)).
- 1.1 changed `Atomic[DType.float32]` to `Atomic[Float32]`: the parameter became a type.

### 3.2 Linear operators: "apply A to x" without a matrix

- **faer (Rust) has one.** `LinOp<T: ComplexField>: Sync + Debug` ([`LinOp`](https://docs.rs/faer/latest/faer/matrix_free/trait.LinOp.html)):
  - `nrows`, `ncols`;
  - `apply(out: MatMut<T>, rhs: MatRef<T>, par: Par, stack: &mut MemStack)` and `conj_apply`;
  - `apply_scratch(rhs_ncols, par) -> StackReq`, the workspace it needs.
  - The right-hand side is a matrix: several vectors at once.
  - Members: dense, sparse (by row and by column) and diagonal matrices, their views, and `&M`. It is dyn compatible.
  - **`BiLinOp: LinOp`** adds `transpose_apply` and `adjoint_apply` ([`BiLinOp`](https://docs.rs/faer/latest/faer/matrix_free/trait.BiLinOp.html)).
  - **`Precond: LinOp`** adds `apply_in_place` and `conj_apply_in_place`, all provided ([`Precond`](https://docs.rs/faer/latest/faer/matrix_free/trait.Precond.html)).
  - Solvers over them: conjugate gradient, BiCGSTAB, LSMR, Krylov–Schur ([matrix_free](https://docs.rs/faer/latest/faer/matrix_free/index.html)). The changelog lists "stabilized matrix-free solvers" in 0.22 ([faer changelog](https://raw.githubusercontent.com/sarah-quinones/faer-rs/main/CHANGELOG.md)).
- **ndarray-linalg (Rust):** `LinearOperator` has `type Elem: Scalar` and six provided methods ([`LinearOperator`](https://docs.rs/ndarray-linalg/latest/ndarray_linalg/operator/trait.LinearOperator.html)):
  - `apply`, `apply_mut`, `apply_into` for vectors, `apply2…` for matrices;
  - `apply` and `apply_mut` default to each other ([source](https://docs.rs/ndarray-linalg/latest/src/ndarray_linalg/operator.rs.html)). A member that overrides neither recurses without end, and the compiler cannot tell.
- **nalgebra (Rust):** none found; the decompositions are structs with inherent methods (§3.4).
- **Swift:** none in the standard library or Swift Numerics. Swift Numerics lists "Shaped Arrays" as future work and sends "more specialized dependencies" (BLAS, LAPACK) to a separate package ([swift-numerics](https://github.com/apple/swift-numerics)).
- **Mojo:** none found. The kernels in `max/kernels/src/linalg` are functions on concrete tensors (§3.3).

### 3.3 Storage: strided, contiguous, fit for BLAS

- **nalgebra:** `Matrix<T, R, C, S>` has dimensions `R` and `C`, each a type-level constant or `Dyn`, and a storage `S` ([`matrix.rs`](https://github.com/dimforge/nalgebra/blob/main/src/base/matrix.rs)).
  - `unsafe trait RawStorage<T, R: Dim, C: Dim>` has the associated `RStride` and `CStride`, and `ptr`, `shape`, `strides`, `is_contiguous` ([`RawStorage`](https://docs.rs/nalgebra/latest/nalgebra/base/storage/trait.RawStorage.html)).
  - It is unsafe because `is_contiguous` "must never" be true for storage that is not, or behaviour is undefined.
  - `Storage` and `StorageMut` add the promise of no uninitialized elements; `IsContiguous` is a marker ([storage](https://docs.rs/nalgebra/latest/nalgebra/base/storage/index.html)).
- **ndarray:** `ArrayBase<S, D>` has a data representation `S: RawData` and a dimension `D: Dimension` ([`ArrayBase`](https://docs.rs/ndarray/latest/ndarray/struct.ArrayBase.html)).
  - `unsafe trait RawData` has the associated `Elem` ([`RawData`](https://docs.rs/ndarray/latest/ndarray/trait.RawData.html)).
  - `Dimension` has `const NDIM: Option<usize>`, `Some` for fixed rank and `None` for `IxDyn` ([`Dimension`](https://docs.rs/ndarray/latest/ndarray/trait.Dimension.html)).
  - **0.17 added reference types** because the fully generic signature is "powerful but verbose and often hard to read" ([RELEASES.md](https://raw.githubusercontent.com/rust-ndarray/ndarray/master/RELEASES.md)). "Use `&ArrayRef<A, D>` to read elements from any array", `&mut ArrayRef<A, D>` to change them, `LayoutRef` for shape and strides only.
  - 0.17.0 was yanked; 0.17.1 fixed "the originally-unsound implementation".
- **Swift:**
  - `Sequence.withContiguousStorageIfAvailable` is an optional capability: it returns `nil` where the storage is not contiguous ([`Sequence.swift`](https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/core/Sequence.swift)).
  - Accelerate's `AccelerateBuffer<Element>` (`count`, `withUnsafeBufferPointer`) and `AccelerateMutableBuffer` build on it ([`AccelerateBuffer`](https://developer.apple.com/documentation/accelerate/acceleratebuffer.md), [`AccelerateMutableBuffer`](https://developer.apple.com/documentation/accelerate/acceleratemutablebuffer.md)).
  - vDSP's functions take them with the element type fixed at the call: `add<T, U, V>(_: T, _: U, result: inout V) where T: AccelerateBuffer, …, T.Element == Double` ([`vDSP.add`](https://developer.apple.com/documentation/accelerate/vdsp/add(_:_:result:)-338hl.md)).
- **Mojo:**
  - `LayoutTensor[dtype, layout: Layout, origin, …]` has a concrete layout with static or run-time dimensions ([`LayoutTensor`](https://max.modular.com/stable/api/mojo/layout/layout_tensor/LayoutTensor)). Its page marks it deprecated for `TileTensor`.
  - `TileTensor[dtype, LayoutType: TensorLayout, origin, Engine: TensorEngine, …]` makes the layout a trait, "so any type implementing `TensorLayout` can describe the tensor's memory arrangement". The engine, a trait too, supplies the storage handle, loads and stores ([`TileTensor`](https://max.modular.com/api/mojo/layout/tile_tensor/TileTensor/)).
  - `NDBuffer`, before both, "is a legacy type", with kernels migrating "gradually" ([forum](https://forum.modular.com/t/relationship-between-ndbuffer-and-layouttensor/1595)).
  - The kernels take the output first and one dtype per operand, plus an accumulator: `gemv_kernel_vector[c_type, a_type, b_type, …, accum_type](c: TileTensor[c_type, …], a: …, b: …, m, n, k)` ([`gemv.mojo`](https://raw.githubusercontent.com/modular/modular/main/max/kernels/src/linalg/gemv.mojo)).

### 3.4 Factorization and solve

- **faer:** `SolveCore<T>: ShapeCore` requires `solve_in_place_with_conj(conj, rhs: MatMut<T>)` and `solve_transpose_in_place_with_conj` ([`SolveCore`](https://docs.rs/faer/latest/faer/linalg/solvers/trait.SolveCore.html)).
  - `Solve<T>` provides 16 methods by a blanket implementation: in place and allocating, for `A`, its conjugate, `Aᵀ` and `Aᴴ`, from the left and from the right ([`Solve`](https://docs.rs/faer/latest/faer/linalg/solvers/trait.Solve.html)).
  - Members: the dense `Llt`, `Ldlt`, `Lblt`, `PartialPivLu`, `FullPivLu`, `Qr`, `ColPivQr`, `Svd`, `SelfAdjointEigen`, and the sparse `Llt`, `Lu`, `Qr` ([solvers](https://docs.rs/faer/latest/faer/linalg/solvers/index.html)).
- **ndarray-linalg:** `Solve<A: Scalar>` requires `solve_inplace`, `solve_t_inplace` and `solve_h_inplace` ([`Solve`](https://docs.rs/ndarray-linalg/latest/ndarray_linalg/solve/trait.Solve.html)).
  - It provides the allocating `solve` and the consuming `solve_into` for each.
  - Members: the factorization `LUFactorized` and the matrix itself, which factorizes at each call.
- **nalgebra:** no shared trait. `LU::solve(&b) -> Option<OMatrix>` and `LU::solve_mut(&mut b) -> bool`; after `false`, `b` "may be left in an unusable state" ([`LU`](https://docs.rs/nalgebra/latest/nalgebra/linalg/struct.LU.html)).
- **Swift, Mojo:** none found.

### 3.5 Mutating and allocating forms

- **Swift's naming rule:** "Name Mutating/nonmutating method pairs consistently": `sort`/`sorted`, `formUnion`/`union` ([API design guidelines](https://www.swift.org/documentation/api-design-guidelines/)). vDSP offers both forms, as in `add(_:_:) -> [Double]` and `add(_:_:result: inout V)` ([vDSP](https://developer.apple.com/documentation/accelerate/vdsp.md)).
- **Rust's libraries** pair them by suffix: `solve` and `solve_mut` (nalgebra); `solve`, `solve_into`, `solve_inplace` (ndarray-linalg); `solve` and `solve_in_place` (faer).
- **In every Rust solver trait seen, the in-place form is the required core** and the allocating ones are provided (§3.4).
- **faer states the workspace:** each operation has a `…_scratch` query returning a `StackReq`, and the caller passes a `MemStack` (§3.2).
- **Mojo's kernels** have the output-first form only (§3.3).

### 3.6 The element type: associated type or parameter

| | Associated type | Trait or type parameter |
|---|---|---|
| Rust | `Iterator::Item`; ndarray `RawData::Elem`, `LinearOperator::Elem`; simba `ComplexField::RealField` | `Extend<A>`, `FromIterator<A>`, `Index<Idx>`; nalgebra `RawStorage<T, R, C>`; faer `LinOp<T>`, `SolveCore<T>`; ndarray-linalg `Solve<A>` |
| Swift | `Sequence.Element`, `AccelerateBuffer.Element`, `SIMDStorage.Scalar`, `VectorProtocol.VectorSpaceScalar` | the concrete types: `Array<Element>`, `Dictionary<Key, Value>` |
| Mojo | `Iterator.Element`, `Iterable.IteratorType` | `List[T]`; a `DType` value for numbers, one per operand in the kernels |

- A Rust trait parameter lets one type be a member at several values. `Vec<T>` is `Extend<T>` and `Extend<&T>`. faer's dense implementations are `LinOp<T>` for any view type `ViewT: Conjugate<Canonical = T>`.

### 3.7 Designs replaced, and why

- **alga's algebra, for simba's coarser traits:** "simpler", and fit for SIMD (§3.1).
- **Functions generic over ndarray's storage, for one reference type:** "verbose and often hard to read" (§3.3).
- **`Numeric` as the root, for `AdditiveArithmetic`:** vectors are not rings (§3.1).
- **Swift for TensorFlow's `VectorProtocol`:** not taken into Swift; `TangentVector` needs only `AdditiveArithmetic` (§3.1).
- **`NDBuffer`, then `LayoutTensor`, for `TileTensor`** with a layout trait (§3.3).
- **Mojo's `==` on `SIMD`:** a mask, then a `Bool` (§2.3).
- **faer's `Entity`:** in 0.20, gone from faer-traits 0.24; no reason found *(uncertain)*.

## 4. What it predicts for us

Each item gives the findings first, then the suggestion. The suggestions are this agent's, for the user and the record to weigh.

### 4.1 The BaseTraits table, row by row

**`Iterable{T}`.**
- Findings:
  - All three languages distinguish one pass from repeatable iteration (§1.1). Swift's designers named the confusion between them as the protocol's main hazard (§2.1).
  - All three carry the iterator's type as an associated type (`IntoIter`, `Iterator`, `IteratorType`).
  - Julia's `iterate(c, state)` is SE-0065's model: the collection advances the position, so no separate iterator borrows the collection. That is why Rust needed generic associated types for an `Iterable` and Mojo needed a borrow-parameterized `IteratorType`.
- Suggestion: state in the contract that `Iterable` promises repeated, nondestructive iteration, as `Collection` does. Base's members in the table (`AbstractArray`, `AbstractDict`) satisfy it. Single-pass iterators (`eachline`, `Iterators.Stateful`) stay out, or join a later `IterableOnce` supertrait.
- Suggestion: the declared result `Union{Nothing, Tuple{T, Any}}` leaves the state at `Any`. Where a loop runs on a value known only by its trait ([reference §7.9](../reference/traits.md#79-operations-on-a-value-the-code-knows-only-by-its-trait)), check by an experiment what the state costs per step. If it boxes, the answer of all three languages is an associated type for it, stated at the membership.
- Suggestion: none of the three puts a size hint in the iteration trait's contract as a promise. Julia's `Base.IteratorSize` already does this job. Note that its value `Base.HasLength()` shares its name with `BaseTraits.HasLength`; the docs should tell them apart.

**`HasLength`.**
- Findings:
  - Rust's length trait cannot be trusted by unsafe code; the trusted one is unsafe and unstable (§1.2).
  - Swift's `count` may be O(n) (§1.3).
  - Mojo has a raising variant, and dropped `Sized` from `Slice`, whose length depends on what it slices (§2.3).
- Suggestion: state that a membership check verifies `length`'s result type, not its value. So trait code must not use `@inbounds` on the strength of a member's `length` alone. A wrong length from a member is then an error, never memory corruption.
- Suggestion: state the expected cost (O(1)) in the contract, as Swift's documentation does for `count`.

**`Indexable{T}` and `MutableIndexable{T}`.**
- Findings:
  - Swift's slices keep their base's indices, and Swift warns against `0` and `count` (§1.3).
  - SE-0191 shows that numeric generality nobody used cost generic code dearly. That argues for `Int` positions, as the table has.
  - Rust pairs a failing `Index` with a non-failing `get` (§1.2).
  - Mojo revised more than once which types may serve as an index (§2.3).
  - `MutableCollection`'s contract: a write keeps the length, and the value stored is read back at that position (§1.3).
- Suggestion: `Indexable{T}`'s members include every `AbstractVector`, so offset axes too. Trait code that loops over `1:length(c)` is then wrong for some members: Swift's `ArraySlice` lesson. Either declare the first position in the contract (`firstindex(c)::Int`, positions `firstindex(c):firstindex(c)+length(c)-1`), or state that positions run from 1 and leave offset vectors out of the membership.
- Suggestion: take Swift's two sentences on writes into `MutableIndexable`'s contract.

**`Resizable`.**
- Findings:
  - Rust grows a `Vec` only with values (`resize(n, value)`, `resize_with(n, f)`); uninitialized growth is `unsafe` (§1.2).
  - Mojo's growth takes a `fill`, or is spelled `unsafe_uninit_length` (§1.4).
  - Swift has no resize. `RangeReplaceableCollection` needs `init()` and `replaceSubrange`, and its `removeAll(where:)` keeps order (§1.3).
  - Rust's insertion traits take the item type as a parameter, since one collection accepts several item types (§1.2).
- Suggestion: Julia's `resize!(v, n)` grows a `Vector` with undefined elements. `retain!` needs only to shrink. Either state `Resizable`'s contract as shrinking (`n ≤ length(c)`), or give growth a value. A trait for appending (`push!`, `append!`) would take its item type as an `@input`, after Rust's `Extend<A>`.
- Aside, not from the prior art: the table gives `resize!` no result type, which [reference §4.1](../reference/traits.md#41-operations) requires of every operation.

**`Keyed{K, V}`.**
- Findings:
  - Neither Rust nor Swift ships a map trait. Rust removed one, and the attempts since stalled on three things: iterating the entries, bounds that differ (`Hash` against `Ord`), and lookup by a borrowed key (§1.2).
  - Swift's draft protocol could not refine `Collection` and left open a split of read from write (§1.3).
  - All three languages' maps offer a lookup that does not fail: Swift's subscript returns an optional, Rust's `get` an `Option`, Mojo's `get(key, default)` a value.
- Suggestion: keep `Keyed` small and read-only. Add `get(d, k, default)::V`, which saves the double lookup of `haskey` then `getindex`. Put writing in a subtrait.
- Suggestion: check that `haskey(d, k::K)` with `K` invariant does not refuse a key that is equal but of another type, such as a `SubString` for `String` keys. That is the case Rust's `Borrow<Q>` exists for.

**`BoundedText`.**
- Findings: none of the three languages' text traits carries a size or a bound (§1.2 to §1.4). Size hints exist only on iterators, and Rust and Mojo both say code must not trust them for safety. Mojo merged its text traits into one writer-based `Writable` (§2.3).
- Suggestion: `BoundedText` has no prior art. Keep it a trait of its own beside printing, and state, as Rust does for `size_hint`, that code which preallocates by `textbound` still checks what `print` wrote.

**`Solvable{T}`:** see §4.2 below.

**Across the table.**
- **Composition.** Mojo removed fourteen named compound traits for `&`, and four one-operator traits that were never apart (§2.3). Swift's advice is one primary associated type per protocol (§1.3). These findings support `All{…}`, bundles as `const` aliases, and traits with one parameter. `HasLength` apart from `Iterable` and `MutableIndexable` apart from `Indexable` match where all three split.
- **Conditional membership.** Mojo tried conformances checked late and replaced them with `where` clauses, to check at compile time (§2.3). Swift's `Array` is `Equatable where Element: Equatable`. Suggestion: where a BaseTraits membership depends on the items (equality, hashing, printing), declare it for the family with a bound on the item type ([reference §5.8](../reference/traits.md#58-families)), not for every item type.
- **Algorithms and their names.** Rust calls its algorithm `retain`, as ours is named. In Swift, an algorithm a member may replace is a customization point, and each one costs and stays forever (§1.3). In Julia every method can be specialized. Suggestion: say per BaseTraits algorithm whether members may specialize it, since a specialization becomes part of its contract.
- **Associated types and the complexity budget.** Swift's `Collection` carries five associated types with constraints between them; Rust's generic associated types took six and a half years. Our item types are equations of `Self`. That keeps the table out of the costly space ([earlier research §8](other-languages-research-2026-10-16.md#8-the-complexity-budget)).

### 4.2 Traits for linear algebra

**`Solvable{T}`.**
- Findings: faer's and ndarray-linalg's solver traits share three choices (§3.4):
  - the required operation solves in place;
  - transposed and adjoint solves are part of the core;
  - the right-hand side is a view of any storage, and in faer a matrix of several columns.
- Suggestion: `solve!(F, x::Vector{T}, b::Vector{T})` excludes views, GPU arrays and the structured state vectors of SciML ports. Type `x` and `b` by a trait, `MutableIndexable{T}` and `Indexable{T}`, or by `AbstractVector{T}`.
- Suggestion: add an adjoint solve, in `Solvable` or a subtrait, as faer's `BiLinOp` splits it. SciML's adjoint sensitivities need it.
- Suggestion: provide the allocating `solve(F, b)` as a default ([reference §4.2](../reference/traits.md#42-defaults)), as both Rust libraries do.
- Suggestion: `T = eltype(Self)` ties the vectors' element type to the factorization's. That excludes mixed precision, such as a `Float32` factorization in iterative refinement of `Float64` vectors. Mojo's kernels keep one element type per operand (§3.3). Consider making the vectors' element type a `where` variable of the operation.

**A linear operator for SciML's matrix-free operators.**
- Findings: faer's `LinOp<T>` is the one design found (§3.2):
  - output first, `apply(out, rhs, …)`, with sizes;
  - the conjugate in the base trait;
  - transpose and adjoint in `BiLinOp`;
  - a preconditioner's in-place application in `Precond`;
  - explicit workspace;
  - several right-hand sides at once.
- ndarray-linalg's `LinearOperator` shows the trap of two defaults defined by each other (§3.2).
- Suggestion: a `LinearOperator{T}` trait with `size`, `mul!(y, A, x)` as the required core and `*` as a default; the adjoint in a subtrait; `ldiv!` in place for preconditioners. Base's `AbstractMatrix` would join as Base's abstract type.
- Suggestion: where a trait offers both `apply!` and `apply` as defaults of each other, the membership check should require at least one of them, a minimal complete definition. Otherwise a member that writes neither passes the check and recurses.

**State vectors and the numeric traits.**
- Findings:
  - Swift's lesson is that a vector space is not a ring. It split `AdditiveArithmetic` out of `Numeric` for vectors, and then asked of differentiable types less than a vector space (§3.1).
  - Rust's fine algebra (alga) gave way to a coarse scalar field trait with an associated real type (simba's `ComplexField::RealField`).
  - Mojo has no tower and generalizes over a closed set of dtypes.
- Suggestion: for ODE state vectors, a small trait of vector operations, not a numeric tower: `zero`, addition, scaling, `axpy!`-style in-place forms, a norm, with the scalar as an associated type.
- Suggestion: for scalars, Julia's closed abstract types (`Real`, `AbstractFloat`, `Complex`) already are the coarse tower, and `real(T)` is simba's associated real type. Base's number types join as those abstract types. Avoid alga's level of detail.

**Storage fit for BLAS.**
- Findings:
  - Rust's storage traits are `unsafe`: a membership that lies about contiguity is undefined behaviour (§3.3).
  - ndarray's users found generic storage parameters too verbose, and got one view type to accept.
  - Mojo made the layout, not the element access, the trait.
  - Swift makes contiguity an optional capability that answers `nil`.
- Suggestion: a strided-storage trait for kernels and BLAS calls: `pointer`, `strides`, `size`, the element type associated. Its contract says that a membership check cannot verify the memory layout, so the membership is the member's promise, as Rust's `unsafe trait` says.
- Suggestion: user-facing functions take a read or write view (`asvector`'s pattern, [reference §10.1](../reference/traits.md#101-basetraits)), not a storage parameter. That is ndarray's 0.17 conclusion.

## Uncertain or unchecked

- The reasons for nalgebra's move from alga to simba beyond the changelog's sentence. The dimforge blog post it cites (2020-04-01) could not be fetched.
- Why faer removed `Entity`. Its changelog records refactors of `Entity` up to 0.15 and no removal.
- `PointwiseMultiplicative` of Swift for TensorFlow, seen only in a search result. Its API page redirected to the archived repository.
- Whether Accelerate declares `Array` an `AccelerateBuffer`. Apple's page lists only `vImage.PixelBuffer` as conforming, but vDSP's own example passes `[Double]`.
- The version label of `LayoutTensor`'s deprecation ("26.7" on the MAX page), which does not match Mojo's 1.x numbering.
- That Mojo's standard library and MAX kernels have no linear-operator trait. The agent read the `linalg` directory listing (shown truncated) and the first half of `gemv.mojo`.
- That Mojo has no trait for `__getitem__` and `__setitem__`. None appears in the pages read.
- That no Rust RFC proposed collection traits after generic associated types became stable. Searches found none.
- That Swift's 2016 multi-pass pitch ended without a proposal. The agent read the thread's opening posts and the current `Sequence` documentation, not the whole thread.
- simba's `ComplexField` implementors as listed on docs.rs. The page shows the `f32` and `f64` implementations under a feature gate. This page does not rely on it.
