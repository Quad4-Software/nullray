from ledger import apply_transactions, top_holders

def test_basic_transfer():
    assert apply_transactions({"a": 100}, [{"src": "a", "dst": "b", "amount": 30}]) == {"a": 70, "b": 30}

def test_insufficient_aborts():
    assert apply_transactions({"a": 10}, [{"src": "a", "dst": "b", "amount": 50}]) == {"a": 10}

def test_tie_break_is_alphabetical():
    b = {"zed": 50, "amy": 50, "bob": 50}
    assert top_holders(b, 2) == [("amy", 50), ("bob", 50)]

def test_top_n_ordering():
    b = {"a": 5, "b": 50, "c": 25}
    assert top_holders(b, 3) == [("b", 50), ("c", 25), ("a", 5)]
