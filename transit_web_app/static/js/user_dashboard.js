const btnLoad = document.getElementById("btnLoad");
const tableBody = document.querySelector("#busTable tbody");
const busTable = document.getElementById("busTable");
const noResultsMsg = document.getElementById("noResultsMsg");

const filterRoute = document.getElementById("filterRoute");
const dateFrom = document.getElementById("dateFrom");
const dateTo = document.getElementById("dateTo");
const tripHeadSign = document.getElementById("tripHeadSign");

// Hide table on load
busTable.style.display = "none";
noResultsMsg.style.display = "block";
noResultsMsg.innerText = "No results yet. Please search.";

function formatDate(dateStr) {
    // Convert to Date object
    const d = new Date(dateStr);

    // Extract YYYY-MM-DD
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');

    return `${day}-${month}-${year}`;
}

async function loadBusData() {
    let url = `/api/busdata?page=1&per_page=50`;

    if (filterRoute.value) url += `&route_id=${filterRoute.value}`;
    if (dateFrom.value) url += `&date_from=${dateFrom.value}`;
    if (dateTo.value) url += `&date_to=${dateTo.value}`;
    if (tripHeadSign.value) url += `&trip_headsign=${tripHeadSign.value}`

    try {
        const res = await fetch(url);
        const data = await res.json();

        tableBody.innerHTML = "";

        if (data.length === 0) {
            busTable.style.display = "none";
            noResultsMsg.style.display = "block";
            noResultsMsg.innerText = "No buses found for selected filters.";
            return;
        }

        noResultsMsg.style.display = "none";
        busTable.style.display = "table";

        data.forEach(row => {
            const tr = document.createElement("tr");
            tr.innerHTML = `
                <td>${formatDate(row.fact_date)}</td>
                <td>${row.arrival_time || '-'}</td>
                <td>${row.departure_time || '-'}</td>
                <td>${row.route_id}</td>
                <td>${row.trip_id}</td>
                <td>${row.trip_headsign || ''}</td>
                <td>${row.ridership_count}</td>
                <td>${row.avg_wait_time_min}</td>
                <td>${row.avg_delay_min}</td>
                <td>${row.fare_collected}</td>
                <td>${row.bus_id}</td>
            `;
            tableBody.appendChild(tr);
        });

    } catch (err) {
        console.error("Error loading bus data:", err);
        busTable.style.display = "none";
        noResultsMsg.style.display = "block";
        noResultsMsg.innerText = "Error loading data.";
    }
}

btnLoad.addEventListener("click", loadBusData);
