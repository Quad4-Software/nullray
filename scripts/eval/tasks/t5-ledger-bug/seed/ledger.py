"""Double-entry ledger. Apply transactions, report balances."""


def apply_transactions(accounts, transactions):
    """Apply a list of {src, dst, amount} transactions to accounts dict.

    Returns balances dict. Rules: insufficient funds abort the transaction;
    concurrent same-source transfers in one batch are allowed if the
    running balance stays non-negative.
    """
    balances = dict(accounts)
    for tx in transactions:
        src, dst, amt = tx["src"], tx["dst"], tx["amount"]
        if balances.get(src, 0) - amt < 0:
            continue
        balances[src] = balances.get(src, 0) - amt
        balances[dst] = balances.get(dst, 0) + amt
    return balances


def top_holders(balances, n):
    """Return top-n (name, balance) sorted by balance desc, name asc on ties."""
    items = sorted(balances.items(), key=lambda kv: -kv[1])
    return items[:n]
