
open Ast_mapper
open Ast_helper
open Asttypes
open Parsetree
open Longident

open Pendulum_compiler

open Utils

module Ast = Sync2ml.Ast



let parse_and_generate atom_mapper vb =
  let e, options, args = Pendulum_parse.parse_args (StringSet.empty) [] vb.pvb_expr in
  let has_opt s = StringSet.mem s options in
  let e, binders, inputs = Pendulum_parse.pop_signals_decl e in
  let sigs = List.(
      inputs @ map Ast.(fun (s, t) -> mk_signal ~origin:Input s, t) args
    )
  in
  if has_opt "ast" then
    [%expr ([%e Pendulum_misc.expr_of_ast @@ Pendulum_parse.ast_of_expr atom_mapper e])]
  else
    let loc = vb.pvb_loc in
    let pat =
      match vb.pvb_pat.ppat_desc with
      | Ppat_var id -> id.txt
      | _ -> "unknown"
    in
    let ast = Pendulum_parse.ast_of_expr atom_mapper e in
    let tast, env = Ast.Tagged.of_ast ~sigs ~binders ast in
    let tast = Ast.Analysis.filter_dead_trees tast in
    Pendulum_misc.print_to_dot (has_opt "dot") (has_opt "pdf") (has_opt "png") loc pat tast;
    let ocaml_expr = Sync2ml.generate options env tast in
    if has_opt "dsource" then Format.printf "%a@." Pprintast.expression ocaml_expr;
    [%expr [%e ocaml_expr]]


let gen_bindings atom_mapper vbl =
  List.map (fun vb ->
      {vb with pvb_expr = parse_and_generate atom_mapper vb}
    ) vbl

let try_compile_error f mapper str =
  let open Sync2ml in
  try f mapper str with
  | Ast.Error (loc, e) ->
    Error.(error ~loc (Other_err (e, Ast.print_error)))
  | Sync2ml.Error (loc, e) ->
    Error.(error ~loc (Other_err (e, Sync2ml.print_error)))
  | Flowgraph.Error (loc, e) ->
    Error.(error ~loc (Other_err (e, Flowgraph.print_error)))
  | Location.Error _ as e -> raise e
  | e ->
    Error.(error ~loc:Ast.dummy_loc
             (Other_err (e, fun fmt e ->
                  Format.fprintf fmt "%s" (Printexc.to_string e))))

let tagged_signals_mapper =
  {default_mapper with
   expr = (fun mapper exp ->
       match exp with
       | [%expr !!([%e? {pexp_desc = Pexp_ident {txt = Lident content; loc}}]
                   ## [%e? {pexp_desc = Pexp_ident {txt = Lident tag_content}}])] ->
         let ident =
           {Ast.content = Format.sprintf "%s##%s" content tag_content; loc}
         in
         let e' =
           [%expr !![%e Sync2ml.Ocaml_gen.mk_ident ident]][@metaloc exp.pexp_loc]
         in
         mapper.expr mapper e'
       | x ->
         default_mapper.expr mapper x
     );
  }

let pendulum_mapper argv =
  let open Sync2ml in
  {default_mapper with
   structure_item = try_compile_error (fun mapper stri ->
       match stri with
       | { pstr_desc = Pstr_extension (({ txt = "sync" }, PStr [
           { pstr_desc = Pstr_value (Nonrecursive, vbs) }]), attrs); pstr_loc } ->
         Str.value Nonrecursive
         @@ gen_bindings (tagged_signals_mapper.expr tagged_signals_mapper) vbs

       | { pstr_desc = Pstr_extension (({ txt = "sync" }, PStr [
           { pstr_desc = Pstr_value (Recursive, _) }]), _); pstr_loc } ->
         Error.(error ~loc:pstr_loc Non_recursive_let)

       | x -> default_mapper.structure_item mapper x
     ) ;

   expr = try_compile_error (fun mapper exp ->
       match exp with
       | { pexp_desc = Pexp_extension ({ txt = "sync"; loc }, e)} ->
         begin match e with
           | PStr [{ pstr_desc = Pstr_eval (e, _)}] ->
             begin match e.pexp_desc with
               | Pexp_let (Nonrecursive, vbl, e) ->
                 Exp.let_ Nonrecursive
                   (gen_bindings (tagged_signals_mapper.expr tagged_signals_mapper) vbl)
                 @@ mapper.expr mapper e
               | Pexp_let (Recursive, vbl, e) ->
                 Error.(error ~loc Non_recursive_let)
               | _ ->
                 Error.(error ~loc Only_on_let)
             end
           | _ -> Error.(error ~loc Only_on_let)
         end
       | x -> default_mapper.expr mapper x;
     )
  }

let () =
  register "pendulum" pendulum_mapper
