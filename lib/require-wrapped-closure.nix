# The doors of the raw-closure applicators: `wrapFn`, the aspect type's `wrapGuardFn`, the guard
# carrier's function fragment, `applyGuard`'s escape-hatch arm, a custom guard form's `eval` and
# `wrapGatedFn`. Each applicator takes a CALLER-SUPPLIED function, so each failure mode of that function gets a door here or a
# falsifier cell in ci/ (den-hoag-g8lo's rule), and a refusal is minted at this library's door, naming this library's entry, rather than
# inside gen-merge's module reader, which names neither (ADR-0025 item 1).
#
# INTERNAL: a door is not a consumer construct, so nothing here is in `lib/default.nix`'s return.
# ACCEPT-LIST: each door names the admitted shape first and refuses everything else.
#
# THE BOUND, stated where a reader meets it. A closure's INPUT is typed totally. Its RETURN is typed
# ONE level: an attrset, or a module function of `cnf.moduleArgs`; what a module function itself
# returns is gen-merge's module reader's contract, not this door's. Its CONTEXT is typed for the
# coords the closure declares, and a closure that declares formals is handed EXACTLY those formals:
# `builtins.functionArgs` erases the ellipsis, so by `functionArgs` a closed pattern cannot be told
# from an open one, and narrowing is the one application total over both (0cmbt §3, N1).
# The same erasure makes an ellipsis-only module function `{ ... }:` indistinguishable from a bare
# formal `q:`, so such a return is refused; its remedy is to name a module arg it reads.
#
# THE SHAPE CLASSIFIER (`requireContextOf`; den-hoag-t5hli ruled arm (a), 0cmbt spec §2.3). A
# function declaring NO formals is classified by its pattern as `builtins.toXML` renders it, because
# `functionArgs` is `{ }` for `x:`, `{ ... }:` and `{ }:` alike: a `<varpat>` (`ctx:`) or an
# ellipsis `<attrspat>` (`{ ... }:`, `a@{ ... }:`, `{ ... }@a:`) is handed the value whole; a bare
# `<attrspat>` with no `<attr>` (`{ }:`, `a@{ }:`) is handed `{ }`; anything else (a primop, or a
# partly applied one) refuses by name. A functor is read through `__functionArgs` when it states one
# (nixpkgs `setFunctionArgs`, a gen-prelude `door`) and through `f.__functor f`'s pattern otherwise.
# `toXML` renders a lambda's pattern, never its body, and forces no formal's default. Every site of
# this door routes through it: `wrapFn`, the aspect type's `wrapGuardFn`, the guard carrier's
# function fragment, `applyGuard`'s escape hatch, and a custom guard form's `eval` at both its
# context position (`{ }: _: true`) and its predicate-argument position (`_: { }: true`).
# `wrapGatedFn` alone keeps `requireRequiredCoords`: its formals are a DECLARATION in its spec
# record, and the function it fires is not the one whose pattern `toXML` could read.
# ITS BOUND, enumerated (ADR-0025 item 1). The classifier reads the OUTERMOST lambda only. A
# forwarding wrapper around `{ }:` (`args: f args`, or a functor stating `__functionArgs = { }` over
# `x:`) classifies as a context and hands the context on, so the inner `{ }:` aborts uncatchably
# inside the wrapper (`called with unexpected argument`). Its remedy is the wrapper's: state the
# inner function's formals, or hand it `{ }` itself.
# OPTION (c), documented beside (a) and NOT taken (t5hli R8's added requirement; owner review of the
# `toXML` dependency flagged at delivery): hand every `functionArgs = { }` shape `{ }`. It is uniform
# and needs no `toXML`; its price is the bare positional `ctx:` aspect (3 CI fixtures in the measured
# v1 corpus, design §3 "S") and a `{ ... }:` handed nothing it could read.
#
# ENUMERATED EXCEPTIONS, each pinned by a falsifier cell: the RETURN of the carrier's function
# fragment and of `applyGuard`'s escape-hatch arm is handed back raw, and `wrapGatedFn`'s result is
# untyped. Those codomains are the guard BODIES' codomain, which den-hoag-lwbb1 decides.
#
# RETIREMENT: this module and every `wrap-totality` cell retire with ADR-0013's closure hatch under
# den-hoag-lwbb1 (first-order guard bodies); they are hatch tests, deleted, not migrated.
#
# COST: no traversal. `requireClosure` is O(1); `requireAspectContent` and `requireRequiredCoords`
# are O(|formals|); rendering a refusal is O(|context|). `requireContextOf entry at f` classifies on
# its partial application to `f`, one `toXML` of `f`'s pattern: `wrapFn` and `wrapGuardFn` bind it
# once per definition, a custom form's context position once per vocabulary; the carrier's function
# fragment, `applyGuard`'s escape hatch and a custom form's predicate-argument position classify at
# every application, since each holds the function only there. So no termination argument is owed.
let
  inherit (builtins)
    attrNames
    concatStringsSep
    filter
    functionArgs
    intersectAttrs
    isAttrs
    isFunction
    match
    toXML
    typeOf
    ;
  names = concatStringsSep ", ";
  # The CONTEXT door over declared formals: refuses a missing required coord, and narrows the context
  # to them. `required` is verbatim `wrapGatedFn`'s binding (lib/types.nix), the predicate
  # `lib/can-take.nix` builds; the disposition is the opposite arm (refuse, never inert), because the
  # native applicator's contract is unconditional (`wrapGatedFn` reaches this door only once its gate
  # holds). `formals` is non-empty at every caller; `requireContextOf` owns the empty case.
  requireRequiredCoords =
    entry: at: formals: ctx:
    if !(isAttrs ctx) then
      throw "gen-aspects.${entry}: the closure at ${at} was applied to a value of type ${typeOf ctx}, not a context; a context is an attrset of coords."
    else
      let
        required = filter (n: !formals.${n}) (attrNames formals);
        missing = filter (n: !(ctx ? ${n})) required;
      in
      if missing == [ ] then
        intersectAttrs formals ctx
      else
        throw (
          "gen-aspects.${entry}: the closure at ${at} requires context coord(s) `${names missing}` that "
          + "the applied context does not carry (context carries: ${names (attrNames ctx)}). Supply them, "
          + "or give the formal a default so the closure can run without it."
        );
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

  inherit requireRequiredCoords;

  # The CONTEXT door over a FUNCTION, the shape classifier stated in the header. Partially applied to
  # `f` it is `f`'s door, so a caller that holds `f` across applications binds it once.
  requireContextOf =
    entry: at: f:
    let
      raw = if isAttrs f then f.__functor f else f;
      formals = if isAttrs f then f.__functionArgs or (functionArgs raw) else functionArgs f;
      xml = toXML raw;
      has = re: match re xml != null;
    in
    if formals != { } then
      requireRequiredCoords entry at formals
    else if has ".*<varpat .*" || has ".*<attrspat[^>]*ellipsis=\"1\".*" then
      ctx: ctx
    else if has ".*<attrspat[^>]*>[[:space:]]*</attrspat>.*" then
      _: { }
    else
      throw (
        "gen-aspects.${entry}: the function at ${at} declares no formals and its pattern cannot be read "
        + "(a primop, or a functor whose __functor does not return a lambda); give it a pattern: `ctx:`, "
        + "`{ ... }:` or a formal set."
      );
}
