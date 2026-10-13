(******************************************************************************)
(*  T2048 — state serialization                                               *)
(*                                                                            *)
(*  The state is a list of bytes: the seed, then a '#', then the numbers of    *)
(*  the game separated by commas — the 16 cells of the board, row by row:     *)
(*     "seed#c0,c1,...,c15"                                                   *)
(******************************************************************************)

From Stdlib Require Import NArith List Strings.Byte.

Import ListNotations.
Local Open Scope N_scope.

(* Game state: the numbers of the game, comma-separated, as a list of bytes *)
Definition state := list byte.

(* Board size; the state holds size * size cells after the seed *)
Definition size := 4%nat.

(* ---- Serialization: numbers to comma-separated bytes ---- *)

Definition digit_byte (d : N) : byte :=
  match d with
  | 0 => x30 | 1 => x31 | 2 => x32 | 3 => x33
  | 4 => x34 | 5 => x35 | 6 => x36 | 7 => x37
  | 8 => x38 | 9 => x39
  | _ => x30
  end.

Fixpoint bytes_of_N (n : N) (fuel : nat) (acc : list byte) : list byte :=
  match fuel with
  | O => acc
  | S fuel' =>
      let acc' := digit_byte (n mod 10) :: acc in
      let q := n / 10 in
      if N.eqb q 0 then acc' else bytes_of_N q fuel' acc'
  end.

Definition show_N (n : N) : list byte := bytes_of_N n 20 nil.

Fixpoint commas (nums : list N) : list byte :=
  match nums with
  | nil => nil
  | n :: nil => show_N n
  | n :: nums' => List.app (show_N n) (x2c :: commas nums')
  end.

Definition state_of_game (s : N) (b : list (list N)) : state :=
  List.app (show_N s) (x23 :: commas (List.concat b)).

(* ---- Parsing: comma-separated bytes to numbers ---- *)

Fixpoint parse_nums (l : list byte) (acc : N) : list N :=
  match l with
  | nil => acc :: nil
  | x2c :: l' => acc :: parse_nums l' 0        (* ',' *)
  | x23 :: l' => acc :: parse_nums l' 0        (* '#' *)
  | x30 :: l' => parse_nums l' (acc * 10 + 0)  (* '0' *)
  | x31 :: l' => parse_nums l' (acc * 10 + 1)  (* '1' *)
  | x32 :: l' => parse_nums l' (acc * 10 + 2)  (* '2' *)
  | x33 :: l' => parse_nums l' (acc * 10 + 3)  (* '3' *)
  | x34 :: l' => parse_nums l' (acc * 10 + 4)  (* '4' *)
  | x35 :: l' => parse_nums l' (acc * 10 + 5)  (* '5' *)
  | x36 :: l' => parse_nums l' (acc * 10 + 6)  (* '6' *)
  | x37 :: l' => parse_nums l' (acc * 10 + 7)  (* '7' *)
  | x38 :: l' => parse_nums l' (acc * 10 + 8)  (* '8' *)
  | x39 :: l' => parse_nums l' (acc * 10 + 9)  (* '9' *)
  | _ :: l' => parse_nums l' acc
  end.

Fixpoint rows (k : nat) (l : list N) : list (list N) :=
  match k with
  | O => nil
  | S k' => firstn size l :: rows k' (skipn size l)
  end.

Definition game_of_state (st : state) : N * list (list N) :=
  let nums := parse_nums st 0 in
  (nth 0 nums 0, rows size (skipn 1 nums)).

(* The round-trip property of the state encoding: serializing a position
   (seed, board) and parsing it back returns the position. The board is
   size * size, and every number fits the 20-digit fuel of the decimal
   serializer (game seeds are 63-bit integers and cells stay far below
   10 ^ 20). *)
Theorem serialize_deserialize :
  forall (s : N) (b : list (list N)),
    length b = size ->
    Forall (fun r => length r = size) b ->
    Forall (fun n => n < 10 ^ 20) (s :: List.concat b) ->
    game_of_state (state_of_game s b) = (s, b).
Proof.
  (* Proof obligation: the decimal round-trip of show_N / parse_nums and
     the rows / concat decomposition of a size * size board. *)
Admitted.
