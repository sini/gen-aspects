# The doors of the raw-closure applicators: `wrapFn`, the aspect type's `wrapGuardFn`, the guard
# carrier's function fragment, `applyGuard`'s escape-hatch arm and `wrapGatedFn`. Each applicator
# takes a CALLER-SUPPLIED function, so each failure mode of that function gets a door here or a
# falsifier cell in ci/ (den-hoag-g8lo's rule), and a refusal is minted at this library's door, naming this library's entry, rather than
# inside gen-merge's module reader, which names neither (ADR-0025 item 1).
#
# INTERNAL: a door is not a consumer construct, so nothing here is in `lib/default.nix`'s return.
# ACCEPT-LIST: each door names the admitted shape first and refuses everything else.
#
# THE BOUND, stated where a reader meets it. A closure's INPUT is typed totally. Its RETURN is typed
# ONE level: an attrset, or a module function of `cnf.moduleArgs`; what a module function itself
# returns is gen-merge's module reader's contract, not this door's. Its CONTEXT is typed only for the
# coords the closure declares: `builtins.functionArgs` erases the ellipsis, so a closed pattern
# applied to an extra coord cannot be told from an open one here, and stays an interpreter abort.
# The same erasure makes an ellipsis-only module function `{ ... }:` indistinguishable from a bare
# formal `q:`, so such a return is refused; its remedy is to name a module arg it reads.
#
# ENUMERATED EXCEPTIONS, each pinned by a falsifier cell: the RETURN of the carrier's function
# fragment and of `applyGuard`'s escape-hatch arm is handed back raw, and `wrapGatedFn`'s result is
# untyped. Those codomains are the guard BODIES' codomain, which den-hoag-lwbb1 decides.
#
# RETIREMENT: this module and every `wrap-totality` cell retire with ADR-0013's closure hatch under
# den-hoag-lwbb1 (first-order guard bodies); they are hatch tests, deleted, not migrated.
#
# COST: no traversal. `requireClosure` is O(1); `requireAspectContent` and `requireRequiredCoords`
# are O(|formals|); rendering a refusal is O(|context|). So no termination argument is owed.
let
  inherit (builtins)
    attrNames
    concatStringsSep
    filter
    functionArgs
    isAttrs
    isFunction
    typeOf
    ;
  names = concatStringsSep ", ";
in
{
  # The INPUT door, on the strict path of the returned record (the `checkedEntry` rule, lib/cnf.nix).
  requireClosure =
    entry: at: fn:
    let
      refuse =
        detail:
        throw (
          "gen-aspects.${entry}: the value wrapped at ${at} must be a raw closure `ctx: <aspect>`; ${detail}. "
          + "Pass the closure itself: the wrap is what makes a closure inspectable, so a value that is "
          + "already a wrap, or is not a closure at all, has nothing to wrap."
        );
    in
    if isFunction fn then
      fn
    else if isAttrs fn && (fn.__isWrappedFn or false) then
      refuse "received a wrap record already built; pass it at the `includes` position rather than wrapping it again"
    else if isAttrs fn && (fn.__guard or false) then
      refuse "received a defunctionalised guard record (`gen-aspects.guard`); it rides the `includes` position as first-order data and is never wrapped"
    else if isAttrs fn then
      refuse "received an attrset no wrap constructor built"
    else
      refuse "received: ${typeOf fn}";

  # `wrapGatedFn`'s two caller functions are APPLIED, never wrapped, so their domain is callable.
  requireCallable =
    entry: what: v:
    if isFunction v || (isAttrs v && v ? __functor) then
      v
    else
      throw "gen-aspects.${entry}: ${what} must be callable (a function, or a record carrying `__functor`); received: ${typeOf v}.";

  # The RETURN door. `isModuleFn` is the discriminator `aspectType`'s merge already routes on
  # (`mkIsModuleFn cnf`), so an applicator admits exactly what the type path admits one level up.
  requireAspectContent =
    entry: at: isModuleFn: v:
    if isAttrs v || (isFunction v && isModuleFn v) then
      v
    else
      throw (
        "gen-aspects.${entry}: the closure at ${at} must return aspect content, an attrset or a module "
        + "function of the declared `cnf.moduleArgs`; "
        + (
          if isFunction v then
            "returned a function whose formals are not module args (`${names (attrNames (functionArgs v))}`; "
            + "empty means a bare formal or an ellipsis-only pattern `{ ... }:`, which cannot be told apart; "
            + "a module function names a module arg it reads, as in `{ config, ... }:`)"
          else
            "returned: ${typeOf v}"
        )
        + ". Return the aspect attrset itself. A closure returning another closure is under-applied: it "
        + "is applied to ONE context and its result merged, so a second parameter is never supplied."
      );

  # The CONTEXT door. `required` is verbatim `wrapGatedFn`'s binding (lib/types.nix), the predicate
  # `lib/can-take.nix` builds; the disposition is the opposite arm (refuse, never inert), because the
  # native applicator's contract is unconditional. A closure declaring no formals reads nothing of
  # its context, so the context is passed through unforced.
  requireRequiredCoords =
    entry: at: formals: ctx:
    if formals == { } then
      ctx
    else if !(isAttrs ctx) then
      throw "gen-aspects.${entry}: the closure at ${at} was applied to a value of type ${typeOf ctx}, not a context; a context is an attrset of coords."
    else
      let
        required = filter (n: !formals.${n}) (attrNames formals);
        missing = filter (n: !(ctx ? ${n})) required;
      in
      if missing == [ ] then
        ctx
      else
        throw (
          "gen-aspects.${entry}: the closure at ${at} requires context coord(s) `${names missing}` that "
          + "the applied context does not carry (context carries: ${names (attrNames ctx)}). Supply them, "
          + "or give the formal a default so the closure can run without it."
        );
}
