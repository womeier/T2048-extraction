(******************************************************************************)
(*  T2048 — state serialization                                               *)
(*                                                                            *)
(*  The state is a list of bytes: the seed, then a '#', then the numbers of    *)
(*  the game separated by commas — the 16 cells of the board, row by row:     *)
(*     "seed#c0,c1,...,c15"                                                   *)
(******************************************************************************)

From Stdlib Require Import NArith List Strings.Byte Lia PeanoNat.

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

(* ---- Round-trip correctness ---- *)

(* 10 ^ k, as a nat-indexed shift by k decimal digits *)
Fixpoint pow10 (k : nat) : N :=
  match k with
  | O => 1
  | S k' => 10 * pow10 k'
  end.

Lemma pow10_eq : forall k, pow10 k = 10 ^ N.of_nat k.
Proof.
  induction k as [|k IH].
  - cbn [pow10]. symmetry; apply N.pow_0_r.
  - cbn [pow10]. rewrite IH.
    rewrite (Nat2N.inj_succ k).
    rewrite (N.pow_succ_r 10 (N.of_nat k) (N.le_0_l _)).
    reflexivity.
Qed.

(* The ten digits, as the only values below 10 *)
Lemma N_lt_10_cases : forall n, n < 10 ->
  n = 0 \/ n = 1 \/ n = 2 \/ n = 3 \/ n = 4 \/
  n = 5 \/ n = 6 \/ n = 7 \/ n = 8 \/ n = 9.
Proof.
  intros n Hn.
  destruct (N.to_nat n) as [|[|[|[|[|[|[|[|[|[|k]]]]]]]]]] eqn:E.
  - left; lia.
  - right; left; lia.
  - right; right; left; lia.
  - right; right; right; left; lia.
  - right; right; right; right; left; lia.
  - right; right; right; right; right; left; lia.
  - right; right; right; right; right; right; left; lia.
  - right; right; right; right; right; right; right; left; lia.
  - right; right; right; right; right; right; right; right; left; lia.
  - right; right; right; right; right; right; right; right; right; lia.
  - lia.
Qed.

(* Reading one digit byte pushes it on the accumulator *)
Lemma parse_nums_digit_byte : forall d l acc,
  d < 10 -> parse_nums (digit_byte d :: l) acc = parse_nums l (acc * 10 + d).
Proof.
  intros d l acc Hd.
  destruct (N_lt_10_cases d Hd) as [H|[H|[H|[H|[H|[H|[H|[H|[H|H]]]]]]]]];
    rewrite H; reflexivity.
Qed.

(* The trailing accumulator is just appended to *)
Lemma bytes_of_N_app : forall fuel n acc,
  bytes_of_N n fuel acc = bytes_of_N n fuel nil ++ acc.
Proof.
  intros fuel; induction fuel as [|f IH]; intros n acc.
  - reflexivity.
  - cbn [bytes_of_N]. destruct (N.eqb (n / 10) 0).
    + reflexivity.
    + rewrite (IH (n / 10) (digit_byte (n mod 10) :: acc)).
      rewrite (IH (n / 10) (digit_byte (n mod 10) :: nil)).
      rewrite <- app_assoc. reflexivity.
Qed.

(* The decimal round-trip of one number: its digits, read back, give the
   number again — shifted up by the digits already in [acc]. *)
Lemma parse_bytes_of_N : forall fuel n l acc,
  n < pow10 fuel ->
  parse_nums (bytes_of_N n fuel nil ++ l) acc =
  parse_nums l (acc * pow10 (length (bytes_of_N n fuel nil)) + n).
Proof.
  intros fuel; induction fuel as [|f IH]; intros n l acc Hn.
  - simpl in Hn. assert (n = 0) by lia. subst n.
    simpl. f_equal. lia.
  - cbn [pow10] in Hn.
    pose proof (N.div_mod n 10 ltac:(discriminate)) as Hdm.
    pose proof (N.mod_upper_bound n 10 ltac:(discriminate)) as Hml.
    cbn [bytes_of_N]. destruct (N.eqb (n / 10) 0) eqn:E.
    + apply N.eqb_eq in E. cbn [app].
      rewrite parse_nums_digit_byte by lia.
      cbn [length]. simpl. f_equal. nia.
    + apply N.eqb_neq in E. rewrite bytes_of_N_app.
      rewrite <- app_assoc.
      rewrite IH by (eapply N.Div0.div_lt_upper_bound; nia).
      cbn [app].
      rewrite parse_nums_digit_byte by lia.
      rewrite length_app. cbn [length]. rewrite Nat.add_1_r.
      cbn [pow10]. f_equal. nia.
Qed.

(* Specialized to a fresh accumulator: parsing [show_N n] yields [n] *)
Lemma parse_show_N : forall n l, n < 10 ^ 20 ->
  parse_nums (show_N n ++ l) 0 = parse_nums l n.
Proof.
  intros n l Hn. unfold show_N. rewrite parse_bytes_of_N.
  - reflexivity.
  - rewrite pow10_eq. exact Hn.
Qed.

(* A non-empty list of numbers, comma-separated, parses back to itself *)
Lemma parse_commas : forall nums,
  nums <> nil ->
  Forall (fun n => n < 10 ^ 20) nums ->
  parse_nums (commas nums) 0 = nums.
Proof.
  induction nums as [|n nums IH]; intros Hnnil Hlt.
  - contradiction.
  - destruct nums as [|m rest].
    + inversion Hlt as [|? ? Hn Hrest]; subst.
      cbn [commas]. rewrite <- (app_nil_r (show_N n)).
      rewrite parse_show_N by exact Hn. reflexivity.
    + inversion Hlt as [|? ? Hn Hrest]; subst.
      cbn [commas]. rewrite parse_show_N by exact Hn.
      cbn [parse_nums]. f_equal. apply IH.
      * discriminate.
      * exact Hrest.
Qed.

(* A size x size board is rebuilt by cutting the flat list into rows *)
Lemma rows_concat : forall b k,
  length b = k ->
  Forall (fun r => length r = size) b ->
  rows k (List.concat b) = b.
Proof.
  induction b as [|r b IH]; intros k Hlen Hrows.
  - cbn in Hlen. subst k. reflexivity.
  - destruct k as [|k']; [discriminate Hlen|].
    inversion Hrows as [|? ? Hr Hb]; subst.
    assert (Hf : firstn size (r ++ List.concat b) = r).
    { rewrite firstn_app, Hr, Nat.sub_diag. cbn [firstn].
      rewrite firstn_all2 by lia. apply app_nil_r. }
    assert (Hs : skipn size (r ++ List.concat b) = List.concat b).
    { rewrite skipn_app, Hr, Nat.sub_diag. cbn [skipn].
      rewrite <- Hr, skipn_all. reflexivity. }
    cbn [List.concat rows].
    rewrite Hf, Hs. f_equal.
    apply IH.
    + cbn in Hlen. injection Hlen as Hlen'. exact Hlen'.
    + exact Hb.
Qed.

(* The round-trip property of the state encoding: serializing a position
   (seed, board) and parsing it back returns the position. *)
Theorem serialize_deserialize :
  forall (s : N) (b : list (list N)),
    length b = size ->
    Forall (fun r => length r = size) b ->
    Forall (fun n => n < 10 ^ 20) (s :: List.concat b) ->
    game_of_state (state_of_game s b) = (s, b).
Proof.
  intros s b Hlen Hrows Hlt.
  inversion Hlt as [|? ? Hs Hcl]; subst.
  assert (Hcnn : List.concat b <> nil).
  { destruct b as [|r b']; [discriminate|].
    inversion Hrows as [|? ? Hr Hb]; subst.
    destruct r as [|x r']; [discriminate|].
    cbn [List.concat]. discriminate. }
  assert (Hparse : parse_nums (state_of_game s b) 0 = s :: List.concat b).
  { unfold state_of_game. rewrite parse_show_N by exact Hs.
    cbn [parse_nums]. f_equal. apply parse_commas; assumption. }
  unfold game_of_state. rewrite Hparse. cbn [nth skipn].
  rewrite rows_concat by assumption. reflexivity.
Qed.
