from app import get_user

def report(user_id):
    rec = get_user(user_id)
    return f"{rec['table']}:{rec['key']}"
