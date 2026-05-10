const statusBox = document.querySelector(".status");

function updateStatus() {
    const statuses = [
        "SYSTEM HEALTHY",
        "ALB ACTIVE",
        "ASG RUNNING",
        "CLOUDWATCH MONITORING",
        "CI/CD CONNECTED"
    ];

    const randomStatus =
        statuses[Math.floor(Math.random() * statuses.length)];

    statusBox.innerText = randomStatus;
}

setInterval(updateStatus, 3000);