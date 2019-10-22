

(* The second homework from Arjun Guha's (UMass) Fall 2018 CS631 'Programming-Languages' class *)
(* https://people.cs.umass.edu/~arjun/courses/compsci631-fall2018/hw/interp.pdf *)

(* Notes 
	Command slash comments a line
	To build and run:
	ocamlbuild -use-ocamlfind -pkg compsci631 -pkg ppx_test interp.d.byte; ./interp.d.byte
	Ocaml runs everything from top down, main method not necessary
	alt g is goto line
	So far this language is immutable, eg it uses rho but not sigma from the lecture 4
	The language now includes closures (See 5.1 in lecture 4) but not addr/stores/hash-tables
*)

(* This is necessary for let%TEST to work. *)
module PTest = Ppx_test.Test

open Interp_util

(* Env is an environment in which an expression exists
	Which maps any number of named ids to entries (Values or held expressions for Fix)
	The current implementation can have multiple occurence of a given variable,
	but the most recent one will take precedent
 *)
type env = (id * entry) list
(* Values are either constants (int/bool) or closures, and are the only valid return for a program execution
	Closure is a function, with the environment it was defined in, id for its argument, and its contents (expression)
	Functions are first-class members, and are valid returns for a program, can be passed partially applied, etc
 *)
and value = 
(* NOTE(kgeffen) This is a little deceptive, this Const is not an expression (exp), but they look the same *)
	| Const of const
	| Closure of env * id * exp
(* NOTE(kgeffen) These lists aren't typed, and won't be until the type-checker is implemented
	Therefore it is fine to have a list of true::2 for example.
	Also intentionally, a list of lists is fine, a list of closures is also fine
 *)
	| List of value list
(* An entry in the environment's lookup table *)
and entry = 
	| Value of value
	| HeldExp of exp

(* Lookup the given identifier in the given environment. Return it as an entry if it's defined *)
let rec lookup (x : id) (r : env) : entry option =
	match r with
		| [] -> None
		| (hd_id, hd_v) :: tl -> if x = hd_id then Some (hd_v) else lookup x tl
	
(* Perform the given binary operation with the values
	For invalid applications (eg true + 3), fail
	Otherwise return the result as a value
 *)
let doOp2 (op : op2) (v1 : value) (v2 : value) : value =
	match op, v1, v2 with
		(* Equality takes any 2 values, of int/bool/closure/list *)
		| Eq, _, _ -> Const (Bool (v1 = v2))
		| LT, Const (Int x), Const (Int y) -> Const (Bool (x < y))
		| GT, Const (Int x), Const (Int y) -> Const (Bool (x > y))
		| Add, Const (Int x), Const (Int y) -> Const (Int (x + y))
		| Sub, Const (Int x), Const (Int y) -> Const (Int (x - y))
		| Mul, Const (Int x), Const (Int y) -> Const (Int (x * y))
		| Div, Const (Int x), Const (Int y) -> Const (Int (x / y))
		| Mod, Const (Int x), Const (Int y) -> Const (Int (x mod y))
		| _ -> failwith "Attempted op2 application with invalid arguments"

(* TODO Long match on full language, deciding not to use optional args *)
let rec interp (e : exp) (r : env) : value =
	match e with
		| Id x -> (match lookup x r with
			| Some (Value v) -> v
			| Some (HeldExp e1) -> interp e1 r
			| _ -> failwith "Free identifier"
		)
		| Const c -> Const c
		| Op2 (op, e1, e2) -> doOp2 op (interp e1 r) (interp e2 r)
		| If (e1, e2, e3) -> (match (interp e1 r) with 
			| Const (Bool true) -> interp e2 r
			| Const (Bool false) -> interp e3 r
			| _ -> failwith "If called with non-bool conditional"
		)
		(* r' has the new binding at its head, preventing past bindings from taking precedence on lookup *)
		| Let (x, e1, e2) -> interp e2 ((x, Value (interp e1 r)) :: r)
		| Fun (x, e1) -> Closure (r, x, e1)
		| Fix (x, e1) -> interp e1 ((x, HeldExp e1) :: r)
		| App (e1, e2) -> (match (interp e1 r) with
			| Closure (rp, ip, ep) -> interp ep ((ip, Value (interp e2 r)) :: rp)
			| _ -> failwith "Attempted function application on something which isn't a function"
		)
		| Empty -> List []
		| Cons (e1, e2) -> (match e2 with 
			(* Single element list, 1::empty *)
			| Empty -> List [interp e1 r]
			| _ -> (match interp e2 r with
				| List lst -> List ((interp e1 r) :: lst)
				| _ -> failwith "Attempted to cons to something which isn't a list"
			)
		)
		| Head e -> (match (interp e r) with
			| List (hd :: tl) -> hd
			| _ -> failwith "Attempted to get head of something which isn't a list"
		)
		| Tail e -> (match (interp e r) with
			| List (hd :: tl) -> List tl
			| _ -> failwith "Attempted to get tail of something which isn't a list"
		)
		| IsEmpty e -> Const (Bool ((interp e r) = List []))
		| Record r -> failwith "not yet implemented"
		| GetField (e, str) -> failwith "not yet implemented"

(* Read the input in the format ./interp.d.byte program
	Where program is a filepath to a program in our grammar
	Assume a single line program (No \n, more than 0 chars)
*)
(* let _ = print_endline (show_exp (from_file Sys.argv.(1)))
let _ = print_endline (show_exp (interp (from_file Sys.argv.(1)) [])) *)



(* TESTS *)
let test_interp_throws ?(r : env = []) (prog : string) : bool =
	try let _ = interp (from_string prog) r in false
	with _ -> true

let test_interp  ?(r : env = []) (prog : string) (res : string) : bool =
	interp (from_string prog) r = interp (from_string res) r

(* -------ID/Let------- *)
let%TEST "Free identifier is invalid" = test_interp_throws "x" ~r:["y", Value(Const(Int 3))]
let%TEST "Bound id is that id's value" = test_interp "x" "3" ~r:["x", Value(Const(Int 3))]
let%TEST "Let binding of single variable with single occurence works" =
	test_interp "let x = 3 + 5 in x" "8"
let%TEST "Let binding of single variable with multiple occurence works" =
	test_interp "let x = 2 in x * x + x" "6"
let%TEST "Let binding x and y to add together works" =
	test_interp "let x = 3 in let y = 4 in x + y" "7"
let%TEST "Let binding x twice respects the innermost occurence" =
	test_interp "let x = 1 in let x = 2 in x" "2"
let%TEST "Let binding x can reference itself if it's been defined in scope" =
	test_interp "let x = 3 in let x = 2 * x in x" "6"
let%TEST "Let x = x in x is invalid when x isn't yet bound" =
	test_interp_throws "let x = x in x"
let%TEST "Let binding a variable doesn't persist it outside of its scope" =
	test_interp_throws "let x = (let y = 3 in 2 + y) in x + y"


(* -------Const------ *)
let%TEST "Constant number is that number" = test_interp "0" "0"
let%TEST "Constant true is true" = test_interp "true" "true"
let%TEST "Constant false is false" = test_interp "false" "false"

(* --------Op2------- *)
let%TEST "2 number addition works" = test_interp "3 + 4" "7"
(* NOTE (kgeffen) leaving it like this to test negatives, ideally find a better way *)
let%TEST "2 number subtraction works" = interp (Op2 (Sub, Const (Int 3), Const (Int 4))) [] = Const (Int (-1))
let%TEST "2 number multiplication works" = test_interp "3 * 4" "12"
let%TEST "2 number division works" = test_interp "12 / 4" "3"
let%TEST "2 number modulo works" = test_interp "12 % 5" "2"
let%TEST "2 number less than works when true" = test_interp "(0 - 10) < 0" "true"
let%TEST "2 number less than works when false" = test_interp "10 < 0" "false"
let%TEST "2 number greater than works when true" = test_interp "5 > 3" "true"
let%TEST "2 number greater than works when false" = test_interp "(0-12) > (0-2)" "false"
let%TEST "2 number equal works when true" = test_interp "7 == 7" "true"
let%TEST "2 number equal works when false" = test_interp "(0-7) == 7" "false"
let%TEST "Equality for number and bool returns false" = test_interp "1 == true" "false"
let%TEST "Equality for bools works" = test_interp "false == false" "true"

let%TEST "Adding 3 numbers works" = test_interp "3 + 7 + 4" "14"
let%TEST "Order of operations respects parenthesis" = test_interp "(7 + 2) * 0" "0"

let%TEST "Adding bools is invalid" = test_interp_throws "true + false"
let%TEST "Dividing by 0 is invalid" = test_interp_throws "12 / 0"
let%TEST "Modding by 0 is invalid" = test_interp_throws "12 mod 0"

(* ---------If----------- *)
let%TEST "If invalid for non-bool conditional" =
	test_interp_throws "if 1 then 1 else 2"
let%TEST "If evaluates to first expression when true" = test_interp "if true then 1 else 2" "1"
let%TEST "If evaluates to second expression when true" = test_interp "if false then 1 else 2" "2"
let%TEST "If can have an more than a const in its conditional" = test_interp "if (7 > 4) then 1 else 2" "1"

(* -----Fun/Fix/App------- *)
let%TEST "Functions are valid return values" = not (test_interp_throws "fun x -> x")
let%TEST "Applying identity function works" = test_interp "(fun x -> x) 3" "3"
let%TEST "Functions can be passed as variables and applied" =
	test_interp "let foo = fun x -> 2*x in foo 3" "6"
let%TEST "Functions retain the env they were defined in" =
	test_interp "let a = 1 in let foo = fun x -> a*x in let a = 2 in foo 1" "1"
let%TEST "Functions can take functions as arguments" =
	test_interp "let double = fun x -> 2*x in let lucky = fun f -> f 7 in lucky double" "14"
let%TEST "Fix works when no recursion occurs" = test_interp "fix x -> if false then x else 3" "3"
let%TEST "Fix recursive implementation of factorial works" =
	test_interp "let y = 5 in fix x -> (if y == 0 then 1 else (y * (let y = y-1 in x)))" "120"

(* --------Lists--------- *)
let%TEST "Empty list is a value" = not (test_interp_throws "empty")
let%TEST "Single int list is a value" = not (test_interp_throws "1::empty")
let%TEST "Single bool list is a value" = not (test_interp_throws "false::empty")
let%TEST "Single closure list is a value" = not (test_interp_throws "(fun x -> 3*x)::empty")
let%TEST "Single list list is a value" = not (test_interp_throws "(1::empty)::empty")
(* NOTE(kgeffen) Mixed type lists are currently valid, but aren't intentional, so aren't tested for *)
let%TEST "List containing operations performs those operations" =
	test_interp "(1+2)::(3*4)::empty" "3::12::empty"
let%TEST "Lists can contain in scope variables" =
	test_interp "let x = 5 in (x+1)::(x*2)::empty" "6::10::empty"
let%TEST "Lists containing in-scope variables resolve those variables on creation" =
	test_interp "let lst = (let x = 5 in (x+1)::(x*2)::empty) in let x = 0 in lst" "6::10::empty"

let%TEST "Head of single int list works" = test_interp "head (1::empty)" "1"
let%TEST "Head of single list list works" = test_interp "head (1::empty)::empty" "1::empty"
let%TEST "Head of multi-element list works" = test_interp "head (1::2::3::4::empty)" "1"

let%TEST "Tail of empty list throws" = test_interp_throws "tail empty"
let%TEST "Tail of single element list is empty" = test_interp "tail (false::empty)" "empty"
let%TEST "Tail of multi-element list is everything after head list" = test_interp "tail (1::2::3::empty)" "2::3::empty"

let%TEST "is_empty true for Empty" = test_interp "is_empty empty" "true"
let%TEST "is_empty false for single element list" = test_interp "is_empty (1::empty)" "false"
let%TEST "is_empty false for single element list where the element is an empty list" =
	test_interp "is_empty ((empty)::empty)" "false"
let%TEST "is_empty false for int, bool, & closure" =
	test_interp "is_empty 1" "false" && test_interp "is_empty true" "false" && test_interp "is_empty (fun x -> 3*x)" "false"


(* Runs all tests declared with let%TEST. This must be the last line
   in the file. *)
let _ = Ppx_test.Test.collect ()
