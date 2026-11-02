"""Filter only infrastructure entries; caller supplies server-authenticated ID."""
def filter_owner_entries(rows, user_id):
    return [row for row in rows if row.get('id') != 'server-monitor' or type(user_id) is int and user_id == 1]
