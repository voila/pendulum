
open Ast_mapper
open Ast_helper
open Asttypes
open Parsetree
open Longident

open Preproc

open Utils


module Error = struct

  let error ~loc rsn =
    raise (Location.Error (
        Location.error ~loc ("[pendulum] " ^ rsn)))

end

let check_ident_string e =
  let open Ast in
  match e.pexp_desc with
  (* | Pexp_construct ({txt = Lident s; loc}, None) *)
  | Pexp_ident {txt = Lident s; loc} ->
    {loc; content = s}
  | _ -> Ast.syntax_error_reason ~loc:e.pexp_loc "variable name expected"

let pop_signals_decl e =
  let cont e =
    match e with
    | [%expr [%e? e_var] [%e? e_value]] -> Ast.mk_vsig (check_ident_string e_var) e_value
    | [%expr [%e? e_var]] ->
      Error.error ~loc:e.pexp_loc ("signal " ^ (check_ident_string e_var).Ast.content ^ " not initialized")
    | _ -> Ast.syntax_error_reason ~loc:e.pexp_loc "signal declaration expected"
  in
  let rec aux sigs p =
    match p with
    | [%expr [%e? params]; [%e? e2] ] ->
      begin match params.pexp_desc with
        | Pexp_tuple ([%expr input [%e? e_var] [%e? e_value]] :: ids)
        | Pexp_tuple ([%expr output [%e? e_var] [%e? e_value]] :: ids)->
          aux (Ast.mk_vsig (check_ident_string e_var) e_value :: ((List.map cont ids) @ sigs)) e2
        | _ ->
          begin match params with
            | [%expr input [%e? e_var] [%e? e_value]]
            | [%expr output [%e? e_var] [%e? e_value]] ->
              aux ((Ast.mk_vsig (check_ident_string e_var) e_value) :: sigs) e2
            | _ -> p, sigs
          end
      end
    | e -> e, sigs
  in aux [] e

let ast_of_expr e =
  let rec visit e =
    let open Ast in
    let open Ast.Derived in
    mk_loc ~loc:e.pexp_loc @@ match e with
    | [%expr nothing] ->
      Nothing

    | [%expr pause] ->
      Pause

    | [%expr emit [%e? signal] [%e? e_value]] ->
      Emit (Ast.mk_vsig (check_ident_string signal) e_value)

    | [%expr exit [%e? label]] ->
      Exit (Label(check_ident_string label))

    | [%expr atom [%e? e]] ->
      Atom e

    | [%expr loop [%e? e]] ->
      Loop (visit e)

    | [%expr [%e? e1]; [%e? e2]] ->
      Seq (visit e1, visit e2)

    | [%expr [%e? e1] || [%e? e2]] ->
      Par (visit e1, visit e2)

    | [%expr present [%e? signal] [%e? e1] [%e? e2]] ->
      Present (check_ident_string signal, visit e1, visit e2)

    | [%expr signal [%e? signal] [%e? e_value] [%e? e]] ->
      Signal (Ast.mk_vsig (check_ident_string signal) e_value, visit e)

    | [%expr suspend [%e? e] [%e? signal]] ->
      Suspend (visit e, check_ident_string signal)

    | [%expr trap [%e? label] [%e? e]] ->
      Trap (Label (check_ident_string label), visit e)

    | [%expr halt ] ->
      Halt

    | [%expr sustain [%e? signal] [%e? e_value]] ->
      Sustain (Ast.mk_vsig (check_ident_string signal) e_value)

    | [%expr present [%e? signal] [%e? e]] ->
      Present_then
        (check_ident_string signal, visit e)

    | [%expr await [%e? signal]] ->
      Await (check_ident_string signal)

    | [%expr abort [%e? e] [%e? signal]] ->
      Abort (visit e, check_ident_string signal)

    | [%expr loopeach [%e? e] [%e? signal]] ->
      Loop_each (visit e, check_ident_string signal)

    | [%expr every [%e? e] [%e? signal]] ->
      Every (check_ident_string signal, visit e)


    | [%expr nothing [%e? e_err]]
    | [%expr pause [%e? e_err]]
    | [%expr emit [%e? _] [%e? e_err]]
    | [%expr exit [%e? _] [%e? e_err]]
    | [%expr atom [%e? _] [%e? e_err]]
    | [%expr loop [%e? _] [%e? e_err]]
    | [%expr [%e? _] || [%e? _] [%e? e_err]]
    | [%expr present [%e? _] [%e? _] [%e? _] [%e? e_err]]
    | [%expr signal [%e? _] [%e? _] [%e? e_err]]
    | [%expr suspend [%e? _] [%e? _][%e? e_err]]
    | [%expr trap [%e? _] [%e? _][%e? e_err]]
    | [%expr halt [%e? e_err]]
    | [%expr sustain [%e? _][%e? e_err]]
    | [%expr present [%e? _] [%e? _][%e? e_err]]
    | [%expr await [%e? _][%e? e_err]]
    | [%expr abort [%e? _] [%e? _] [%e? e_err]]
    | [%expr loopeach [%e? _] [%e? _][%e? e_err]]
    | [%expr every [%e? _] [%e? _] [%e? e_err]] ->
      Ast.(syntax_error_reason ~loc:e_err.pexp_loc "maybe you forgot a `;`")

    | [%expr input [%e? _ ] ; [%e? _]] ->
      Error.error ~loc:e.pexp_loc "signal declarations must be at the begining"

    | e -> Ast.(syntax_error_reason ~loc:e.pexp_loc "keyword expected")
  in visit e

let parse_ast loc ext e =
  let e, sigs = pop_signals_decl e in
  begin match ext with
    | "sync_ast" ->
      [%expr ([%e Pendulum_misc.expr_of_ast @@ ast_of_expr e])]

    | "to_dot_grc" ->
      let ast = ast_of_expr e in
      let tast, env = Ast.Tagged.of_ast ~sigs ast in
      Pendulum_misc.print_to_dot loc tast;
      let ocaml_expr =
        Sync2ml.generate ~sigs:(sigs, env.Ast.Tagged.all_local_signals) tast in
      Format.printf "%a@." Pprintast.expression ocaml_expr;
      [%expr [%e Pendulum_misc.expr_of_ast ast]]

    | "sync" ->
      let ast = ast_of_expr e in
      let tast, env = Ast.Tagged.of_ast ~sigs ast in
      let ocaml_expr =
        Sync2ml.generate ~sigs:(sigs, env.Ast.Tagged.all_local_signals) tast in
      [%expr [%e ocaml_expr]]

    | _ -> assert false
  end


let gen_bindings ext vbl =
  List.map (fun vb ->
      {vb with pvb_expr = parse_ast vb.pvb_loc ext vb.pvb_expr}
    ) vbl


let expected_ext = Utils.StringSet.(
    add "to_dot_grc" (
      add "sync_ast" (
        singleton "sync" )))

let extend_mapper argv = {
  default_mapper with
    structure_item = (fun mapper stri -> match stri with
      | { pstr_desc = Pstr_extension (({ txt = ext }, PStr [
          { pstr_desc = Pstr_value (Nonrecursive, vbs) }]), attrs); pstr_loc }
        when StringSet.mem ext expected_ext ->

        (Str.value Nonrecursive (gen_bindings ext vbs))

      | { pstr_desc = Pstr_extension (({ txt = ext }, PStr [
          { pstr_desc = Pstr_value (Recursive, _) }]), _); pstr_loc }
        when StringSet.mem ext expected_ext ->
            Error.error ~loc:pstr_loc "non recursive `let` expected"

      | x -> default_mapper.structure_item mapper x
      );

    expr = fun mapper expr -> match expr with
      | { pexp_desc = Pexp_extension ({ txt = ext; loc }, e)}
        when StringSet.mem ext expected_ext ->
        begin try
            begin match e with
              | PStr [{ pstr_desc = Pstr_eval (e, _)}] ->
                begin match e.pexp_desc with
                  | Pexp_let (Nonrecursive, vbl, e) ->
                    Exp.let_ Nonrecursive (gen_bindings ext vbl)
                      @@ mapper.expr mapper e
                  | Pexp_let (Recursive, vbl, e) ->
                    Error.error ~loc "non recursive `let` expected"
                  | _ ->
                    Error.error ~loc "`let` expected"
                end
              | _ -> Error.error ~loc "only allowed on let"
            end
          with
          | Ast.Error (loc, e) ->
            Error.error ~loc (Format.asprintf "%a" Ast.print_error e)
          | Sync2ml.Error (loc, e) ->
            Error.error ~loc (Format.asprintf "%a" Sync2ml.print_error e)
        end
      | x -> default_mapper.expr mapper x;
  }

let () = register "pendulum" extend_mapper
