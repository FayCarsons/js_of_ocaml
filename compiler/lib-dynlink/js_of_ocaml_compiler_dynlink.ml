open Js_of_ocaml_compiler.Stdlib
open Js_of_ocaml_compiler
module J = Jsoo_runtime.Js

type bytecode_sections =
  { symb : Ocaml_compiler.Symtable.GlobalMap.t
  ; crcs : (string * Digest.t option) list
  ; prim : string list
  ; dlpt : string list
  }
[@@ocaml.warning "-unused-field"]

external get_bytecode_sections : unit -> bytecode_sections = "jsoo_get_bytecode_sections"

let () =
  let global = J.pure_js_expr "globalThis" in
  Config.Flag.set "use-js-string" (Jsoo_runtime.Sys.Config.use_js_string ());
  Config.Flag.set "effects" (Jsoo_runtime.Sys.Config.effects ());
  (* this needs to stay synchronized with toplevel.js *)
  let toplevel_compile (s : string) (debug : Instruct.debug_event list array) :
      unit -> J.t =
    let prims = Array.of_list (Ocaml_compiler.Symtable.all_primitives ()) in
    let b = Buffer.create 100 in
    let fmt = Pretty_print.to_buffer b in
    Driver.configure fmt;
    Driver.from_string ~prims ~debug s fmt;
    Format.(pp_print_flush std_formatter ());
    Format.(pp_print_flush err_formatter ());
    flush stdout;
    flush stderr;
    let js = Buffer.contents b in
    let res : string -> unit -> J.t =
      Obj.magic (J.get global (J.string "toplevelEval"))
    in
    res (js : string)
  in
  let toplevel_eval (x : string) : unit -> J.t =
    let f : J.t = J.eval_string x in
    fun () ->
      let res = J.fun_call f [| global |] in
      Format.(pp_print_flush std_formatter ());
      Format.(pp_print_flush err_formatter ());
      flush stdout;
      flush stderr;
      res
  in
  let toc = get_bytecode_sections () in
  let sym =
    let t : Ocaml_compiler.Symtable.GlobalMap.t = toc.symb in
    Ocaml_compiler.Symtable.GlobalMap.fold
      (fun i n acc -> StringMap.add (Ocaml_compiler.Symtable.Global.name i) n acc)
      t
      StringMap.empty
  in
  let toplevel_reloc (name : J.t) : int =
    let name = J.to_string name in
    match StringMap.find_opt name sym with
    | Some i -> i
    | None -> Js_of_ocaml_compiler.Ocaml_compiler.Symtable.reloc_ident name
  in
  J.set global (J.string "toplevelCompile") (Obj.magic toplevel_compile) (*XXX HACK!*);
  J.set global (J.string "toplevelEval") (Obj.magic toplevel_eval);
  J.set global (J.string "toplevelReloc") (Obj.magic toplevel_reloc)
