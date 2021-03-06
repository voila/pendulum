(** Grc module

    The GRC is the intermediate representation of the synchronous language. It
    corresponds to :

    * a Selection_tree which is an execution environnment carrying the information of
    which statement is currently active or not
    * a Flowgraph which is basically the function executing a logical instant
    * a Schedule module to transforme the flowgraph, check for causality cicles and
    remvoe Fork nodes.

    The GRC method appears in the case of Esterel in the Compiling Esterel book,
    where you can find compilation rules and details. It is also explained in
    Pendulum's related papers.

    All those transformations use a heavy amount of hash-consing (memoization of
    data-structures), to represent flowgraph as DAGs instead of trees. It is
    then easier to schedule and compile, and it allow to compare graphs by
    physical comparison.

    The interface of Grc modules is represented as functors, as the Ast module
    is, so it is independant of the underlying general purpose language (OCaml
    Parsetree for example).

*)


module Selection_tree : sig

  module type S = sig

    module Ast : Ast.S

    type t = {label : int; t : repr; mutable tested : bool}
    and repr =
      | Bottom
      | Pause
      | Par of t list
      | Excl of t list
      | Ref of t

    val print_to_dot : Format.formatter -> t -> unit
    val of_ast : Ast.Tagged.t -> t

  end

  module Make (Ast : Ast.S) : S with module Ast = Ast

end

module Flowgraph : sig

  module type S = sig

    module Ast : Ast.S

    type action =
      | Emit of Ast.valued_signal
      | Atom of Ast.atom
      | Enter of int
      | Exit of int
      | Local_signal of Ast.valued_signal
      | Instantiate_run of Ast.ident * Ast.signal list * Ast.loc

    type test_value =
      | Signal of Ast.signal * Ast.atom option
      | Selection of int
      | Sync of (int * int)
      | Is_paused of Ast.ident * Ast.signal list * Ast.loc
      | Finished

    type t =
      | Call of action * t
      | Test of test_value * t * t * t option (* then * else *)
      | Fork of t * t * t (* left * right * sync *)
      | Pause
      | Finish

    type flowgraph = t

    module Fgtbl : Hashtbl.S with type key = flowgraph
    module FgEmitsTbl : Hashtbl.S with type key = flowgraph * flowgraph * Ast.signal
    module Fgtbl2 : Hashtbl.S with type key = flowgraph * flowgraph
    module Fgtbl3 : Hashtbl.S with type key = flowgraph * flowgraph * flowgraph
    module Fgstbl : Hashtbl.S with type key = flowgraph list

    val print_to_dot : Format.formatter -> t -> unit
    val pp : Format.formatter -> t -> unit
    val pp_dot : Format.formatter -> t -> unit
    val pp_test_value : Format.formatter -> test_value -> unit
    val pp_action: Format.formatter -> action -> unit

    val test_node : test_value -> t * t * t option -> t
    val sync_node : int * int -> t * t * t option -> t

    val (>>) : action -> t -> t
    val exit_node : Ast.Tagged.t -> t -> t
    val enter_node : Ast.Tagged.t -> t -> t


    type error =
      | Unbound_label of string
      | Cyclic_causality of t
      | Par_leads_to_finish of t

    val error : loc:Ast.loc -> error -> 'a

    exception Error of Ast.loc * error
    val print_error : Format.formatter -> error -> unit
  end

  module Make (Ast : Ast.S) : S with module Ast = Ast

end


module Of_ast : sig

  module type S = sig

    module Ast : Ast.S
    module Fg : Flowgraph.S
    module St : Selection_tree.S

    val flowgraph : Ast.Tagged.t -> Fg.t
    (** construct only the flowgraph *)

    val construct : Ast.Tagged.t -> St.t * Fg.t
    (** construct the grc structure from the ast and returns both
     the flowgraph and the selection tree *)

  end

  module Make (Fg : Flowgraph.S) (St : Selection_tree.S with module Ast = Fg.Ast) : S
    with module Ast = Fg.Ast
     and module Fg = Fg
     and module St = St

end

module Schedule : sig

  module type S = sig

    module Ast : Ast.S
    module Fg : Flowgraph.S
    module St : Selection_tree.S

    val check_causality_cycles : 'a * Fg.t -> Fg.t list Ast.SignalMap.t

    val tag_tested_stmts : St.t -> Fg.t -> unit
    val find : bool -> Fg.t -> Fg.t -> Fg.t option
    val find_and_replace :
      (Fg.t -> Fg.t) ->
      Fg.t -> Fg.t -> bool * Fg.t

    val find_join : bool -> Fg.t -> Fg.t -> Fg.t option
    val replace_join : Fg.t -> Fg.t -> (Fg.t -> Fg.t)
      -> Fg.t * Fg.t
    val children: Fg.t -> Fg.t -> Fg.t -> Fg.t

    val interleave: Fg.t -> Fg.t
    (** It basically linearize the flowgraph by removing all the Fork
        The algorithm is rather naive and could be optimized.*)

  end

  module Make (Fg : Flowgraph.S) (St : Selection_tree.S with module Ast = Fg.Ast) : S
    with module Ast = Fg.Ast
     and module Fg = Fg
     and module St = St

end
