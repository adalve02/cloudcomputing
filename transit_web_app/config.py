# config.py

# --- Database Configuration ---
DB_CONFIG = {
    'host': 'localhost',  
    'user': 'root',            
    'password': 'Labhijakshrahate02@', 
    'database': 'ltc_transit'   ,
}

# --- Flask Configuration ---
FLASK_CONFIG = {
    # CHANGE THIS TO A LONG, RANDOM STRING FOR PRODUCTION SECURITY
    'SECRET_KEY': 'a_very_secret_key_for_session_management_12345', 
    'DEBUG': True 
}
