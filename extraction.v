(******************************************************************************)
(*  T2048 — Wasm extraction via CertiRocq                                     *)
(*                                                                            *)
(*    init_with_seed : N -> state                                             *)
(*    move : direction * state -> state * message                             *)
(*                                                                            *)
(*  The top-level record t2048_wasm_api bundles all entry points so that a    *)
(*  single Wasm module contains the whole game (one shared linear memory).    *)
(*  The FFI helpers dir_of_nat / message_tag give the JavaScript side stable  *)
(*  encodings, so no constructor numbering is hard-coded in the browser.      *)
(******************************************************************************)

From Stdlib Require Import NArith List.
From Top Require Import T2048.
From CertiRocq.Plugin Require Import CertiRocq.

Import ListNotations.

(* Direction of a move, as exposed to the front-end *)
Inductive direction :=
  | DUp | DDown | DLeft | DRight.

(* Outcome of a move, as reported to the front-end *)
Inductive message :=
  | MsgInvalid   (* the move does not change the board *)
  | MsgLost      (* no empty cell left after the move *)
  | MsgWon       (* 2048 tile reached *)
  | MsgContinue. (* the game goes on *)

(* Game state: a seed steering tile placement, and the board *)
Record state := MkState {
  st_seed  : N;
  st_board : list (list N)
}.

Definition size := 4%nat.
Definition gen_values := 2 :: 4 :: nil.
Definition target := 2048.

Definition to_move (d : direction) : move :=
  match d with
  | DUp    => Um
  | DDown  => Dm
  | DLeft  => Lm
  | DRight => Rm
  end.

Definition init_with_seed (s : N) : state :=
  match add_val s gen_values (make_board size) with
  | Some (s1, b1) => MkState s1 b1
  | None => MkState s (make_board size)
  end.

Definition move (p : direction * state) : state * message :=
  let '(d, st) := p in
  match
    next_board size (st_seed st) gen_values target
             (to_move d) (st_board st)
  with
  | iresult  => (st, MsgInvalid)
  | lresult => (st, MsgLost)
  | wresult => (st, MsgWon)
  | vresult s1 b1 => (MkState s1 b1, MsgContinue)
  end.

(* ---- FFI helpers for the JavaScript front-end ---- *)

Definition dir_of_nat (n : nat) : direction :=
  match n with
  | O => DUp
  | S O => DDown
  | S (S O) => DLeft
  | S (S (S O)) => DRight
  | _ => DUp
  end.

Definition message_tag (m : message) : nat :=
  match m with
  | MsgInvalid   => 0
  | MsgLost      => 1
  | MsgWon       => 2
  | MsgContinue  => 3
  end.

(* Single entry point: everything ends up in one Wasm module.
   The record gives the JavaScript side a single block holding one
   closure per field, in field order. *)
Record wasm_api := MkWasmApi {
  api_move           : direction * state -> state * message;
  api_dir_of_nat     : nat -> direction;
  api_message_tag    : message -> nat;
  api_init_with_seed : N -> state
}.

Definition t2048_wasm_api : wasm_api :=
  {| api_move := move;
     api_dir_of_nat := dir_of_nat;
     api_message_tag := message_tag;
     api_init_with_seed := init_with_seed |}.

Eval vm_compute in (init_with_seed 0).

CertiRocq Compile Wasm t2048_wasm_api.
