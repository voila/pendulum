(** Sync2ml module
    This module agregates all the function to transform from the Ast to
    OCaml. It calls the Grc module and compiles the flowgraph to a pseudo
    ML language with barely nothing except `if`, assignements, `let`, sequence,
    ocaml expressions and grc primitives (emit, enter, exit, ...).

    This language is then easily compiled to OCaml in the module OCaml_gen

*)


module Expression : sig
  type t = Parsetree.expression
  val print : Format.formatter -> t -> unit
  module Location : Ast.Location
end

module Ast : Ast.S
  with type exp = Parsetree.expression
   and type loc = Location.t
   and type core_type = Parsetree.core_type

module Flowgraph : Grc.Flowgraph.S with module Ast = Ast
module Selection_tree : Grc.Selection_tree.S with module Ast = Ast

module Schedule : Grc.Schedule.S with module Fg = Flowgraph

module Of_ast : Grc.Of_ast.S
  with module Fg = Flowgraph
   and module Ast = Ast
   and module St = Selection_tree

type error = Noerr

exception Error of Location.t * error
val print_error : Format.formatter -> error -> unit

type ml_test_expr =
  | MLsig of Ast.signal
  | MLselect of int
  | MLor of ml_test_expr * ml_test_expr
  | MLand of ml_test_expr * ml_test_expr
  | MLboolexpr of Ast.atom
  | MLfinished
  | MLis_pause of ml_ast

and ml_sequence =
  | Seqlist of ml_ast list
  | Seq of ml_sequence * ml_sequence
and ml_ast =
  | MLemit of Ast.valued_signal
  | MLif of ml_test_expr * ml_sequence * ml_sequence
  | MLassign_signal of Ast.ident * ml_ast
  | MLassign_machine of int * (Ast.ident * Ast.signal list * Ast.loc)
  | MLenter of int
  | MLexit of int
  | MLenters_exits of (Utils.Bitset.t * Utils.Bitset.t)
  | MLexpr of Ast.atom
  | MLunitexpr of Ast.atom
  | MLpause
  | MLfinish
  | MLcall of Ast.ident * Ast.signal list * Ast.loc

module Ocaml_gen : sig
  val mk_ident : Ast.ident -> Parsetree.expression
end

val pp_ml_sequence : int -> Format.formatter -> ml_sequence -> unit

val grc2ml : int list array -> Flowgraph.t -> ml_sequence

val generate: Utils.StringSet.t ->
  Ast.Tagged.env -> Ast.Tagged.t -> Parsetree.expression
