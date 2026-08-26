# Shared aspect-schema construction for the PURE gen tree (value-injection).
#
# NON-module helper: the leading underscore excludes it from the import-tree tree load (the
# import-tree fork skips `/_`-prefixed paths). It is imported by relative path from setup.nix and
# namespace.nix so both share ONE `mkAspectSchema` cnf. The cnf ARGUMENT itself lives in
# ./_aspect-cnf.nix — flake.nix reads the same declaration for gen-delivery's `project`, so the
# schema the tree is composed under and the key-category declaration the realization predicate
# reads cannot drift.
{ genAspects, lib }: genAspects.mkAspectSchema (import ./_aspect-cnf.nix { inherit lib; })
