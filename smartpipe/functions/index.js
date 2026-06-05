const functions = require("firebase-functions");
const nodemailer = require("nodemailer");

// Configure email transporter with Gmail
const transporter = nodemailer.createTransporter({
  service: "gmail",
  auth: {
    user: "2201102887@student.buksu.edu.ph", // Replace with your new email
    pass: "qqdywbgpkogircil", // Replace with your new app password
  },
});

exports.sendEmail = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const {
      to,
      subject,
      deviceName,
      message,
      flowRate,
      timestamp,
      systemName,
    } = req.body;

    // Validate required fields
    if (!to || !subject || !deviceName || !message) {
      return res.status(400).json({
        success: false,
        error: "Missing required fields",
      });
    }

    // Create HTML email content
    const htmlContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>${subject}</title>
        </head>
        <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
          <div style="max-width: 600px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
            <!-- Header -->
            <div style="background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; padding: 30px 20px; text-align: center;">
              <h1 style="margin: 0; font-size: 28px; font-weight: bold;">🚨 WATER LEAK ALERT</h1>
              <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">
                ${systemName || "SmartPipe Water Management System"}
              </p>
            </div>

            <!-- Alert Icon -->
            <div style="text-align: center; padding: 30px 20px;">
              <div style="width: 80px; height: 80px; background: #dc2626; border-radius: 50%; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center;">
                <span style="font-size: 40px;">⚠️</span>
              </div>
              <h2 style="color: #dc2626; margin: 0 0 10px 0; font-size: 24px;">IMMEDIATE ACTION REQUIRED</h2>
              <p style="color: #666; margin: 0; font-size: 16px; line-height: 1.5;">
                A water leak has been detected in your SmartPipe system. Please take immediate action to prevent water damage.
              </p>
            </div>

            <!-- Alert Details -->
            <div style="padding: 0 20px 30px;">
              <div style="background: #f8f9fa; border-radius: 8px; padding: 20px; margin-bottom: 20px;">
                <h3 style="margin: 0 0 15px 0; color: #333; font-size: 18px;">🚨 Alert Details</h3>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-bottom: 15px;">
                  <div>
                    <strong style="color: #666; font-size: 14px;">Device:</strong>
                    <p style="margin: 5px 0 0 0; color: #333; font-size: 16px;">${deviceName}</p>
                  </div>
                  <div>
                    <strong style="color: #666; font-size: 14px;">Flow Rate:</strong>
                    <p style="margin: 5px 0 0 0; color: #333; font-size: 16px;">${flowRate || "N/A"}</p>
                  </div>
                </div>

                <div style="margin-bottom: 15px;">
                  <strong style="color: #666; font-size: 14px;">Message:</strong>
                  <p style="margin: 5px 0 0 0; color: #333; font-size: 16px; line-height: 1.4;">${message}</p>
                </div>

                <div>
                  <strong style="color: #666; font-size: 14px;">Timestamp:</strong>
                  <p style="margin: 5px 0 0 0; color: #333; font-size: 16px;">${timestamp || new Date().toLocaleString()}</p>
                </div>
              </div>

              <!-- Action Steps -->
              <div style="background: #fff3cd; border: 1px solid #ffeaa7; border-radius: 8px; padding: 20px; margin-bottom: 20px;">
                <h3 style="margin: 0 0 15px 0; color: #856404; font-size: 18px;">🔧 Immediate Action Steps</h3>
                <ol style="margin: 0; padding-left: 20px; color: #856404; line-height: 1.6;">
                  <li>Check the affected area immediately</li>
                  <li>Turn off the main water supply if necessary</li>
                  <li>Contact maintenance if the issue persists</li>
                  <li>Monitor the SmartPipe app for updates</li>
                </ol>
              </div>

              <!-- Contact Information -->
              <div style="background: #e3f2fd; border: 1px solid #bbdefb; border-radius: 8px; padding: 20px;">
                <h3 style="margin: 0 0 15px 0; color: #1976d2; font-size: 18px;">📞 Need Help?</h3>
                <p style="margin: 0 0 10px 0; color: #1976d2; line-height: 1.5;">
                  If you need immediate assistance or have questions about this alert, please contact our support team.
                </p>
                <p style="margin: 0; color: #1976d2; font-weight: bold;">
                  Support: support@smartpipe.com | Emergency: +1-800-SMART-PIPE
                </p>
              </div>
            </div>

            <!-- Footer -->
            <div style="background: #f8f9fa; padding: 20px; text-align: center; border-top: 1px solid #e9ecef;">
              <p style="margin: 0 0 10px 0; color: #666; font-size: 14px;">
                This is an automated alert from your SmartPipe Water Management System.
              </p>
              <p style="margin: 0; color: #666; font-size: 12px;">
                © 2024 SmartPipe. All rights reserved.
              </p>
            </div>
          </div>
        </body>
      </html>
    `;

    // Send email
    const mailOptions = {
      from: "SmartPipe Alert <2201102887@student.buksu.edu.ph>", // Replace with your new email
      to: to,
      subject: subject,
      html: htmlContent,
    };

    const result = await transporter.sendMail(mailOptions);

    console.log("Email sent successfully:", result.messageId);

    res.status(200).json({
      success: true,
      messageId: result.messageId,
      message: "Email sent successfully",
    });
  } catch (error) {
    console.error("Error sending email:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Health check endpoint
exports.health = functions.https.onRequest((req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.json({
    status: "healthy",
    service: "SmartPipe Email Service",
    timestamp: new Date().toISOString(),
  });
}); 