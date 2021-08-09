# CompactPlacemark

This package provides support for caching CLPlacemark data in a compact form. CLPlacemark is codable but results in data in excess of 6Kb. CompactPlacemark results in data of a few hundred bytes. CompactPlacemark also provides information about the locale at a given location and has support for converting values into price and number strings for that locale.  CompactPlacemark can perform a large number of reverse lookup operations without error using a scheduling queue that paces the operations.
