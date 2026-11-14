# Fail before media acquisition when the speech bundle is absent

Video Voice Studio formerly discovered a missing F5 bundle only after acquiring and analyzing source media. The existing bundle-presence guard now runs before acquisition or local copying. This saves unnecessary download, storage and analysis work in an incomplete build, while preserving the same explicit unavailable-engine error and retained-job recovery path.

This is only a presence preflight. It does not certify model integrity, native runtime compatibility, inference, word accuracy or voice resemblance. Those checks still occur at their existing stages; native execution remains unverified here. A source-order regression checks that the guard precedes acquisition and local copying.
