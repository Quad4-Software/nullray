from db import fetch_record

def get_user(user_id):
    return fetch_record("users", user_id)

def get_post(post_id):
    return fetch_record("posts", post_id)
