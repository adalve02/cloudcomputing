from flask import Flask, jsonify, request, render_template, redirect, url_for, flash
import mysql.connector
from mysql.connector import Error
from config import DB_CONFIG, FLASK_CONFIG
from flask_cors import CORS
from flask import session, redirect, url_for
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
#from werkzeug.security import check_password_hash
from werkzeug.security import generate_password_hash, check_password_hash
import datetime

# --- Flask App and Config Setup ---
app = Flask(__name__, template_folder='templates', static_folder='static')
app.config.update(FLASK_CONFIG)
CORS(app)

# ===============================================
# 🔗 Database Connection
# ===============================================
def get_db_connection():
    try:
        return mysql.connector.connect(**DB_CONFIG)
    except Error as e:
        print(f"Error connecting to MySQL: {e}")
        return None

# ===============================================
# 🔑 Flask-Login Setup and User Model
# ===============================================
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login' 
login_manager.login_message_category = 'info' 

class User(UserMixin):
    def __init__(self, id, username, role, password_hash):
        self.id = id
        self.username = username
        self.role = role
        self.password_hash = password_hash

    def get_id(self):
        return str(self.id)

@login_manager.user_loader
def load_user(user_id):
    conn = get_db_connection()
    if not conn: return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id, username, role, password_hash FROM users WHERE id = %s", (user_id,))
        user_data = cursor.fetchone()
        cursor.close()
        if user_data:
            return User(user_data['id'], user_data['username'], user_data['role'], user_data['password_hash'])
        return None
    finally:
        if conn.is_connected(): conn.close()

# ===============================================
# 🌐 ROUTES: Authentication
# ===============================================
@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        if current_user.role == 'admin':
            return redirect(url_for('dashboard'))
        else:
            return redirect(url_for('user_dashboard'))

    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        conn = get_db_connection()
        if not conn:
            flash("Database connection failed.", "danger")
            return render_template('login.html')
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute(
                "SELECT id, username, role, password_hash FROM users WHERE username = %s",
                (username,)
            )
            user_data = cursor.fetchone()
            cursor.close()
            
            if user_data and check_password_hash(user_data['password_hash'], password):
                db_user = User(user_data['id'], user_data['username'], user_data['role'], user_data['password_hash'])
                login_user(db_user)
                flash('Logged in successfully.', 'success')
                
                # Redirect based on role
                if db_user.role == 'admin':
                    return redirect(url_for('dashboard'))
                else:
                    return redirect(url_for('user_dashboard'))

            flash('Invalid username or password.', 'danger')
        finally:
            if conn.is_connected():
                conn.close()

    return render_template('login.html')


# ===============================================
# 🖼️ ROUTES: Web Pages
# ===============================================
@app.route('/')
def index():
    if not current_user.is_authenticated:
        return redirect(url_for('login'))
    return redirect(url_for('dashboard'))

@app.route('/dashboard')
@login_required
def dashboard():
    if current_user.role != 'admin':
        flash('Access denied. Admin privileges required.', 'warning')
        return redirect(url_for('index'))
    return render_template('dashboard.html', user=current_user)

# ===============================================
# 📊 API: Dashboard Data
# ===============================================
@app.route('/api/busdata', methods=['GET'])
@login_required
def api_busdata():
    page = int(request.args.get('page', 1))
    per_page = int(request.args.get('per_page', 50))
    route_id = request.args.get('route_id')
    date_from = request.args.get('date_from')
    date_to = request.args.get('date_to')
    trip_headsign = request.args.get('trip_headsign')

    offset = (page - 1) * per_page
    params = []
    filters = []

    if route_id:
        filters.append("rf.route_id = %s")
        params.append(route_id)
    if date_from:
        filters.append("rf.fact_date >= %s")
        params.append(date_from)
    if date_to:
        filters.append("rf.fact_date <= %s")
        params.append(date_to)
    if trip_headsign:
        filters.append("t.trip_headsign LIKE %s")
        params.append(f"%{trip_headsign}%")


    where = "WHERE " + " AND ".join(filters) if filters else ""

    query = f"""
    SELECT 
        rf.fact_date,
        rf.route_id,
        rf.trip_id,
        t.trip_headsign,
        t.arrival_time,
        t.departure_time,
        rf.ridership_count,
        rf.avg_wait_time_min,
        rf.avg_delay_min,
        rf.fare_collected,
        rf.weather_code,
        rf.bus_id,
        rf.driver_id
    FROM ridership_fact rf
    LEFT JOIN trip t ON rf.trip_id = t.trip_id
    {where}
    ORDER BY rf.fact_date DESC
    LIMIT %s OFFSET %s
"""
    params.extend([per_page, offset])

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "DB connection failed"}), 500
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(query, params)
        rows = cursor.fetchall()
        for r in rows:
           if isinstance(r.get("arrival_time"), (datetime.time, datetime.timedelta)):
             r["arrival_time"] = str(r["arrival_time"])
           if isinstance(r.get("departure_time"), (datetime.time, datetime.timedelta)):
             r["departure_time"] = str(r["departure_time"])  
        return jsonify(rows)
    finally:
        if conn.is_connected(): cursor.close(); conn.close()

@app.route('/api/metrics', methods=['GET'])
@login_required
def api_metrics():
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "DB connection failed"}), 500
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT fact_date, SUM(ridership_count) as total_riders
            FROM ridership_fact
            GROUP BY fact_date
            ORDER BY fact_date DESC
            LIMIT 30
        """)
        rows = [{"date": r[0].isoformat(), "total_riders": int(r[1])} for r in cursor.fetchall()]
        return jsonify(rows)
    finally:
        if conn.is_connected(): cursor.close(); conn.close()

# ===============================================
# ➕ API: Admin Insert Ridership
# ===============================================
@app.route('/api/insert_ridership', methods=['POST'])
@login_required
def api_insert_ridership():
    if current_user.role != 'admin':
        return jsonify({"error": "Admin access required"}), 403

    data = request.get_json()
    if not data:
        return jsonify({"error": "No data provided"}), 400

    required_fields = ['fact_date','arrival_time','departure_time','trip_id','route_id',
                       'ridership_count','avg_wait_time_min','avg_delay_min',
                       'fare_collected','weather_code','bus_id','driver_id']

    if any(field not in data for field in required_fields):
        return jsonify({"error": "Missing required fields"}), 400

    DEFAULT_SERVICE_ID = '3302'
    
    try:
        fact_date = datetime.datetime.strptime(data['fact_date'], '%Y-%m-%d').date()
        is_weekend = fact_date.weekday() >= 5

        params = (
            data['fact_date'],
            data['arrival_time'],
            data['departure_time'],
            data['trip_id'],
            DEFAULT_SERVICE_ID,
            data['route_id'],
            not is_weekend,
            is_weekend,
            data['ridership_count'],
            data['avg_wait_time_min'],
            data['avg_delay_min'],
            data['fare_collected'],
            data['weather_code'],
            data['bus_id'],
            data['driver_id']
        )

        query = """
            INSERT INTO ridership_fact 
            (fact_date, arrival_time, departure_time, trip_id, service_id, route_id, weekday, weekend,
             ridership_count, avg_wait_time_min, avg_delay_min,
             fare_collected, weather_code, bus_id, driver_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """

        conn = get_db_connection()
        if not conn:
            return jsonify({"error": "DB connection failed"}), 500

        cursor = conn.cursor()
        print("Insert params:", params)  # Debug: check values
        cursor.execute(query, params)
        conn.commit()
        return jsonify({"message": "Ridership data inserted successfully"}), 201

    except Error as e:
        return jsonify({"error": f"Database insertion failed: {str(e)}"}), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()



# ===============================================
@app.route('/api/bus_dropdown')
@login_required
def bus_dropdown():
    conn = get_db_connection()
    if not conn: return jsonify([])
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT DISTINCT bus_id FROM ridership_fact")
        rows = cursor.fetchall()
        return jsonify(rows)
    finally:
        if conn.is_connected(): cursor.close(); conn.close()

@app.route('/api/driver_dropdown')
@login_required
def driver_dropdown():
    conn = get_db_connection()
    if not conn: return jsonify([])
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT DISTINCT driver_id FROM ridership_fact")
        rows = cursor.fetchall()
        return jsonify(rows)
    finally:
        if conn.is_connected(): cursor.close(); conn.close()
#user dashboard route
@app.route('/user_dashboard')
@login_required
def user_dashboard():
    if current_user.role == 'admin':
        flash('Admins should use the admin dashboard.', 'warning')
        return redirect(url_for('dashboard'))
    return render_template('user_dashboard.html', user=current_user)
#new user registration route
@app.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')

        if not username or not password:
            flash('Please fill all fields', 'warning')
            return render_template('register.html')

        hashed_pw = generate_password_hash(password)

        conn = get_db_connection()
        if not conn:
            flash('Database connection failed', 'danger')
            return render_template('register.html')

        try:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO users (username, role, password_hash) VALUES (%s, %s, %s)",
                (username, 'user', hashed_pw)
            )
            conn.commit()
            flash('Registration successful! Please login.', 'success')
            return redirect(url_for('login'))
        except mysql.connector.Error as e:
            flash(f'Error: {str(e)}', 'danger')
            return render_template('register.html')
        finally:
            if conn.is_connected():
                cursor.close()
                conn.close()

    return render_template('register.html')
#logout route
@app.route('/logout')
def logout():
    session.clear()  # or session.pop('user_id', None)
    return redirect(url_for('login'))
# ===============================================
# 🚀 Run Flask App
# ===============================================
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
