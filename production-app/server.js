const express = require("express");
const os = require("os");

const app = express();

const PORT = 3000;

// Middleware logging
app.use((req, res, next) => {
    console.log(
        `[${new Date().toISOString()}] ${req.method} ${req.url}`
    );
    next();
});

// Health check route
app.get("/health", (req, res) => {
    res.status(200).json({
        status: "healthy"
    });
});

// Main route
app.get("/", (req, res) => {

    const hostname = os.hostname();

    const networkInterfaces = os.networkInterfaces();

    let privateIP = "Not Found";

    for (const interfaceName in networkInterfaces) {

        for (const net of networkInterfaces[interfaceName]) {

            if (
                net.family === "IPv4" &&
                !net.internal
            ) {
                privateIP = net.address;
            }
        }
    }

    res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Production DevOps Platform</title>

        <style>
            body {
                background: #0f172a;
                color: white;
                font-family: Arial;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
            }

            .container {
                text-align: center;
                background: #1e293b;
                padding: 40px;
                border-radius: 12px;
                width: 600px;
            }

            .status {
                background: green;
                padding: 10px;
                margin-top: 20px;
                border-radius: 8px;
            }

            .info {
                margin-top: 20px;
                text-align: left;
            }

            .info p {
                margin: 10px 0;
            }
        </style>
    </head>

    <body>

        <div class="container">

            <h1>Production Cloud Platform</h1>

            <p>
                Terraform + AWS + Docker + ALB + ASG + CloudWatch
            </p>

            <div class="status">
                SYSTEM HEALTHY
            </div>

            <div class="info">

                <p>
                    <strong>Container ID / Hostname:</strong>
                    ${hostname}
                </p>

                <p>
                    <strong>Private IP:</strong>
                    ${privateIP}
                </p>

                <p>
                    <strong>Health Endpoint:</strng>
                    /health
                </p>

            </div>

        </div>

    </body>
    </html>
    `);
});

app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});