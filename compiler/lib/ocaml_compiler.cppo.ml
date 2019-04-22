(* Js_of_ocaml compiler
 * http://www.ocsigen.org/js_of_ocaml/
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

open Stdlib

let rec obj_of_const =
  let open Lambda in
  let open Asttypes in
  function
  | Const_base (Const_int i) -> Obj.repr i
  | Const_base (Const_char c) -> Obj.repr c
  | Const_base (Const_string (s,_)) -> Obj.repr s
  | Const_base (Const_float s) -> Obj.repr (float_of_string s)
  | Const_base (Const_int32 i) -> Obj.repr i
  | Const_base (Const_int64 i) -> Obj.repr i
  | Const_base (Const_nativeint i) -> Obj.repr i
  | Const_immstring s -> Obj.repr s
  | Const_float_array sl ->
    let l = List.map ~f:float_of_string sl in
    Obj.repr (Array.of_list l)
#ifdef BUCKLESCRIPT
  | Const_pointer (i,_) ->
    Obj.repr i
  | Const_block (tag,_,l) ->
    let b = Obj.new_block tag (List.length l) in
    List.iteri (fun i x ->
      Obj.set_field b i (obj_of_const x)
    ) l;
    b
#else
  | Const_pointer i ->
    Obj.repr i
  | Const_block (tag,l) ->
    let b = Obj.new_block tag (List.length l) in
    List.iteri ~f:(fun i x ->
      Obj.set_field b i (obj_of_const x)
    ) l;
    b
#endif

let rec find_loc_in_summary ident' = function
  | Env.Env_empty -> None
  | Env.Env_value (_summary, ident, description)
    when ident = ident' ->
    Some description.Types.val_loc
  | Env.Env_value (summary,_,_)
  | Env.Env_type (summary, _, _)
  | Env.Env_extension (summary, _, _)
#if OCAML_VERSION >= (4,8,0)
  | Env.Env_module (summary, _, _,_)
#else
  | Env.Env_module (summary, _, _)
#endif
  | Env.Env_modtype (summary, _, _)
  | Env.Env_class (summary, _, _)
  | Env.Env_cltype (summary, _, _)
#if OCAML_VERSION >= (4,8,0)
  | Env.Env_open (summary, _)
#elif OCAML_VERSION >= (4,7,0)
  | Env.Env_open (summary, _, _)
#else
  | Env.Env_open (summary, _)
#endif
  | Env.Env_functor_arg (summary, _)
#if OCAML_VERSION >= (4,4,0)
  | Env.Env_constraints (summary, _)
#endif
#if OCAML_VERSION >= (4,6,0)
  | Env.Env_copy_types (summary, _)
#endif
#if OCAML_VERSION >= (4,8,0)
  | Env.Env_persistent (summary, _)
#endif
   -> find_loc_in_summary ident' summary

#if OCAML_VERSION < (4,8,0)
(* Copied from ocaml/utils/tbl.ml *)
module Tbl = struct
  type ('a, 'b) t =
    | Empty
    | Node of ('a, 'b) t * 'a * 'b * ('a, 'b) t * int

  let empty = Empty

  let height = function
    | Empty -> 0
    | Node (_, _, _, _, h) -> h

  let create l x d r =
    let hl = height l and hr = height r in
    Node (l, x, d, r, if hl >= hr then hl + 1 else hr + 1)

  let bal l x d r =
    let hl = height l and hr = height r in
    if hl > hr + 1
    then
      match l with
      | Node (ll, lv, ld, lr, _) when height ll >= height lr ->
         create ll lv ld (create lr x d r)
      | Node (ll, lv, ld, Node (lrl, lrv, lrd, lrr, _), _) ->
         create (create ll lv ld lrl) lrv lrd (create lrr x d r)
      | _ -> assert false
    else if hr > hl + 1
    then
      match r with
      | Node (rl, rv, rd, rr, _) when height rr >= height rl ->
         create (create l x d rl) rv rd rr
      | Node (Node (rll, rlv, rld, rlr, _), rv, rd, rr, _) ->
         create (create l x d rll) rlv rld (create rlr rv rd rr)
      | _ -> assert false
    else create l x d r

  let rec add x data = function
    | Empty -> Node (Empty, x, data, Empty, 1)
    | Node (l, v, d, r, h) ->
       let c = compare x v in
       if c = 0
       then Node (l, x, data, r, h)
       else if c < 0
       then bal (add x data l) v d r
       else bal l v d (add x data r)

  let rec iter f = function
    | Empty -> ()
    | Node (l, v, d, r, _) -> iter f l; f v d; iter f r

  let rec find compare x = function
    | Empty -> raise Not_found
    | Node (l, v, d, r, _) ->
       let c = compare x v in
       if c = 0 then d else find compare x (if c < 0 then l else r)

  let rec fold f m accu =
    match m with
    | Empty -> accu
    | Node (l, v, d, r, _) -> fold f r (f v d (fold f l accu))
end

module Symtable = struct

  type 'a numtable =
    { num_cnt : int
    ; num_tbl : ('a, int) Tbl.t }

  module GlobalMap = struct
    type t = Ident.t numtable

    let filter_global_map p gmap =
      let newtbl = ref Tbl.empty in
      Tbl.iter (fun id num -> if p id then newtbl := Tbl.add id num !newtbl) gmap.num_tbl;
      {num_cnt = gmap.num_cnt; num_tbl = !newtbl}

    let find nn t =
      Tbl.find
        (fun x1 x2 -> String.compare (Ident.name x1) (Ident.name x2))
        nn
        t.num_tbl

    let iter nn t = Tbl.iter nn t.num_tbl

    let fold f t acc = Tbl.fold f t.num_tbl acc
  end
end
#else
module Symtable = struct

  (* Copied from ocaml/bytecomp/symtable.ml *)
  module Num_tbl (M : Map.S) = struct
    [@@@ocaml.warning "-32"]

    type t = {
        cnt: int; (* The next number *)
        tbl: int M.t ; (* The table of already numbered objects *)
      }

    let empty = { cnt = 0; tbl = M.empty }

    let find key nt =
      M.find key nt.tbl

    let iter f nt =
      M.iter f nt.tbl

    let fold f nt a =
      M.fold f nt.tbl a

    let enter nt key =
      let n = !nt.cnt in
      nt := { cnt = n + 1; tbl = M.add key n !nt.tbl };
      n

    let incr nt =
      let n = !nt.cnt in
      nt := { cnt = n + 1; tbl = !nt.tbl };
      n

  end
  module GlobalMap = struct
    module GlobalMap = Num_tbl(Ident.Map)
    include GlobalMap

    let filter_global_map p (gmap : t) =
      let newtbl = ref Ident.Map.empty in
      Ident.Map.iter
        (fun id num -> if p id then newtbl := Ident.Map.add id num !newtbl)
        gmap.tbl;
      {cnt = gmap.cnt; tbl = !newtbl}
  end

end
#endif

module Ident = struct
  (* Copied from ocaml/typing/ident.ml *)
  type 'a tbl' =
    | Empty
    | Node of 'a tbl' * 'a data * 'a tbl' * int

  and 'a data =
    { ident : Ident.t
    ; data : 'a
    ; previous : 'a data option }

    type 'a tbl = 'a Ident.tbl

  let rec table_contents_rec sz t rem =
    match t with
    | Empty -> rem
    | Node (l, v, r, _) ->
       table_contents_rec
         sz
         l
         ((sz - v.data, Ident.name v.ident, v.ident) :: table_contents_rec sz r rem)

  let table_contents sz (t : 'a tbl) =
    List.sort
      ~cmp:(fun (i, _, _) (j, _, _) -> compare i j)
      (table_contents_rec sz (Obj.magic (t : 'a tbl) : 'a tbl') [])

end