const form = document.getElementById("ridershipForm");
const msgDiv = document.getElementById("insert-message");
const tableBody = document.querySelector("#busTable tbody");
const chartCanvas = document.getElementById("chart");

// Dropdowns
const busSelect = document.getElementById("bus_id");
const driverSelect = document.getElementById("driver_id");

// Weather mapping
const weatherMap = {1:'Sunny', 2:'Cloudy', 3:'Rain', 4:'Snow', 5:'Windy'};

// Load dropdowns
async function loadDropdowns() {
    try {
        const [busRes, driverRes] = await Promise.all([
            fetch('/api/bus_dropdown'),
            fetch('/api/driver_dropdown')
        ]);

        const buses = await busRes.json();
        const drivers = await driverRes.json();

        busSelect.innerHTML = '';
        buses.forEach(b => {
            const opt = document.createElement('option');
            opt.value = b.bus_id;
            opt.text = b.bus_id;
            busSelect.appendChild(opt);
        });

        driverSelect.innerHTML = '';
        drivers.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.driver_id;
            opt.text = d.driver_id;
            driverSelect.appendChild(opt);
        });
    } catch(err) {
        console.error("Error loading dropdowns:", err);
    }
}

// Format date YYYY-MM-DD
function formatDate(dateStr) {
    const d = new Date(dateStr);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2,'0');
    const day = String(d.getDate()).padStart(2,'0');
    return `${year}-${month}-${day}`;
}

// Load ridership table
async function loadBusData() {
    try {
        const res = await fetch("/api/busdata?page=1&per_page=50");
        const data = await res.json();
        tableBody.innerHTML = '';

        data.forEach(row => {
            const tr = document.createElement("tr");
            tr.innerHTML = `
                <td>${row.fact_date}</td>
                <td>${row.arrival_time || '-'}</td>
                <td>${row.departure_time || '-'}</td>
                <td>${row.route_id}</td>
                <td>${row.trip_id}</td>
                <td>${row.trip_headsign || ''}</td>
                <td>${row.ridership_count}</td>
                <td>${row.avg_wait_time_min}</td>
                <td>${row.avg_delay_min}</td>
                <td>${row.fare_collected}</td>
                <td>${weatherMap[parseInt(row.weather_code)] || '-'}</td>
                <td>${row.bus_id}</td>
                <td>${row.driver_id}</td>
            `;
            tableBody.appendChild(tr);
        });
    } catch(err) {
        console.error("Error loading table:", err);
    }
}

// Load chart
async function loadMetrics() {
    try {
        const res = await fetch("/api/metrics");
        const data = await res.json();
        const ctx = chartCanvas.getContext("2d");

        new Chart(ctx, {
            type: 'line',
            data: {
                labels: data.map(d => d.date),
                datasets: [{
                    label: 'Total Riders',
                    data: data.map(d => d.total_riders),
                    borderColor: "#004080",
                    backgroundColor: "rgba(0, 64, 128, 0.3)",
                    fill: true,
                    tension: 0.3
                }]
            },
            options: { responsive: true, maintainAspectRatio: false }
        });
    } catch(err) {
        console.error("Error loading chart:", err);
    }
}

// Form submission
if(form && msgDiv){
    form.addEventListener("submit", async (e) => {
        e.preventDefault();

        // Append seconds to time inputs
        const arrivalTime = form.arrival_time.value.length === 5 ? form.arrival_time.value + ':00' : form.arrival_time.value;
        const departureTime = form.departure_time.value.length === 5 ? form.departure_time.value + ':00' : form.departure_time.value;

        const data = {
            fact_date: form.fact_date.value,
            arrival_time: arrivalTime,
            departure_time: departureTime,
            route_id: form.route_id.value,
            trip_id: form.trip_id.value,
            ridership_count: parseInt(form.ridership_count.value),
            avg_wait_time_min: parseFloat(form.avg_wait_time_min.value),
            avg_delay_min: parseFloat(form.avg_delay_min.value),
            fare_collected: parseFloat(form.fare_collected.value),
            weather_code: parseInt(form.weather_code.value),
            bus_id: form.bus_id.value,
            driver_id: form.driver_id.value
        };

        try {
            const res = await fetch("/api/insert_ridership", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify(data)
            });

            const result = await res.json();
            if(res.ok){
                msgDiv.style.color = "green";
                msgDiv.innerText = result.message || "Inserted successfully!";
                form.reset();
                loadBusData();
                loadMetrics();
            } else {
                msgDiv.style.color = "red";
                msgDiv.innerText = result.error || "Error inserting data";
            }
        } catch(err){
            console.error(err);
            msgDiv.style.color = "red";
            msgDiv.innerText = "Unexpected error inserting data";
        }
    });
}

// Initial load
loadDropdowns();
loadBusData();
loadMetrics();
