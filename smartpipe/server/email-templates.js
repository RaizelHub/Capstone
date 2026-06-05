// Shared email templates for SmartPipe Water Management System

const emailTemplates = {
  // Daily Consumption Report Template
  dailyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const reportDate = data.date ? new Date(data.date).toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) : new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Daily Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #0ea5e9, #0284c7); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">💧</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Daily Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${reportDate}</p>
          </div>

          <!-- Total Consumption Highlight -->
          <div style="background: linear-gradient(135deg, #ecfeff, #cffafe); padding: 30px; margin: 30px; border-radius: 12px; text-align: center; border: 2px solid #06b6d4;">
            <div style="font-size: 14px; color: #0891b2; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Consumption</div>
            <div style="font-size: 48px; font-weight: 700; color: #0e7490; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
            <div style="font-size: 18px; color: #0891b2; font-weight: 500;">Liters</div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Breakdown</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #0ea5e9;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                  <div>
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 28px; font-weight: 700; color: #0ea5e9;">${liters.toFixed(1)}</div>
                    <div style="font-size: 12px; color: #64748b;">Liters</div>
                  </div>
                </div>
                <div style="background-color: #e0f2fe; border-radius: 8px; height: 8px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #0ea5e9, #0284c7); height: 100%; width: ${percentage}%; border-radius: 8px; transition: width 0.3s ease;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of total consumption</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #0ea5e9; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Weekly Consumption Report Template
  weeklyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const avgDaily = totalConsumption / 7;
    const startDate = data.startDate ? new Date(data.startDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '';
    const endDate = data.endDate ? new Date(data.endDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '';
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Weekly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #8b5cf6, #7c3aed); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📅</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Weekly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${startDate} - ${endDate}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #faf5ff, #f3e8ff); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #a78bfa;">
              <div style="font-size: 14px; color: #7c3aed; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Weekly</div>
              <div style="font-size: 36px; font-weight: 700; color: #6d28d9; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 16px; color: #7c3aed; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 14px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Daily Average</div>
              <div style="font-size: 36px; font-weight: 700; color: #b45309; margin: 10px 0;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 16px; color: #d97706; font-weight: 500;">Liters/Day</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Performance</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const dailyAvg = liters / 7;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #8b5cf6;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #8b5cf6;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Week)</div>
                    <div style="font-size: 14px; color: #7c3aed; margin-top: 4px; font-weight: 600;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #f3e8ff; border-radius: 8px; height: 8px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #8b5cf6, #7c3aed); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of weekly total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #8b5cf6; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Monthly Consumption Report Template
  monthlyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const daysInMonth = data.daysInMonth || 30;
    const avgDaily = totalConsumption / daysInMonth;
    const monthName = data.month ? new Date(2024, data.month - 1, 1).toLocaleDateString('en-US', { month: 'long' }) : new Date().toLocaleDateString('en-US', { month: 'long' });
    const year = data.year || new Date().getFullYear();
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Monthly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📊</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Monthly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${monthName} ${year}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #d1fae5, #a7f3d0); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #34d399;">
              <div style="font-size: 12px; color: #059669; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Monthly</div>
              <div style="font-size: 32px; font-weight: 700; color: #047857; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 14px; color: #059669; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #dbeafe, #bfdbfe); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #60a5fa;">
              <div style="font-size: 12px; color: #2563eb; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Daily Average</div>
              <div style="font-size: 32px; font-weight: 700; color: #1e40af; margin: 10px 0;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 14px; color: #2563eb; font-weight: 500;">Liters/Day</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 12px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Est. Monthly</div>
              <div style="font-size: 32px; font-weight: 700; color: #b45309; margin: 10px 0;">${(avgDaily * 30).toFixed(0)}</div>
              <div style="font-size: 14px; color: #d97706; font-weight: 500;">Liters</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Analysis</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const dailyAvg = liters / daysInMonth;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #10b981;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #10b981;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Month)</div>
                    <div style="font-size: 14px; color: #059669; margin-top: 4px; font-weight: 600;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #d1fae5; border-radius: 8px; height: 10px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #10b981, #059669); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of monthly total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #10b981; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Yearly Consumption Report Template
  yearlyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const avgDaily = totalConsumption / 365;
    const avgMonthly = totalConsumption / 12;
    const year = data.year || new Date().getFullYear();
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Yearly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📈</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Yearly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">Annual Report ${year}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 30px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 14px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Annual</div>
              <div style="font-size: 42px; font-weight: 700; color: #b45309; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 16px; color: #d97706; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #dbeafe, #bfdbfe); padding: 30px; border-radius: 12px; text-align: center; border: 2px solid #60a5fa;">
              <div style="font-size: 14px; color: #2563eb; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Monthly Average</div>
              <div style="font-size: 42px; font-weight: 700; color: #1e40af; margin: 10px 0;">${avgMonthly.toFixed(1)}</div>
              <div style="font-size: 16px; color: #2563eb; font-weight: 500;">Liters/Month</div>
            </div>
          </div>

          <div style="padding: 0 30px 20px 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background-color: #f8fafc; padding: 20px; border-radius: 10px; text-align: center; border: 1px solid #e2e8f0;">
              <div style="font-size: 12px; color: #64748b; font-weight: 600; text-transform: uppercase; margin-bottom: 6px;">Daily Average</div>
              <div style="font-size: 28px; font-weight: 700; color: #1e293b;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 14px; color: #64748b;">Liters/Day</div>
            </div>
            <div style="background-color: #f8fafc; padding: 20px; border-radius: 10px; text-align: center; border: 1px solid #e2e8f0;">
              <div style="font-size: 12px; color: #64748b; font-weight: 600; text-transform: uppercase; margin-bottom: 6px;">Total Devices</div>
              <div style="font-size: 28px; font-weight: 700; color: #1e293b;">${devices.length}</div>
              <div style="font-size: 14px; color: #64748b;">Active Devices</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Annual Device Performance</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const monthlyAvg = liters / 12;
              const dailyAvg = liters / 365;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #f59e0b;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #f59e0b;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Year)</div>
                    <div style="font-size: 13px; color: #d97706; margin-top: 4px; font-weight: 600;">${monthlyAvg.toFixed(1)} L/month</div>
                    <div style="font-size: 12px; color: #92400e; margin-top: 2px;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #fef3c7; border-radius: 8px; height: 10px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #f59e0b, #d97706); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of annual total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #f59e0b; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Summary Report Template (Comprehensive)
  summaryReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Water Consumption Summary Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📑</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Comprehensive Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">Summary Report</p>
          </div>

          <!-- Total Consumption Highlight -->
          <div style="background: linear-gradient(135deg, #eef2ff, #e0e7ff); padding: 35px; margin: 30px; border-radius: 12px; text-align: center; border: 3px solid #6366f1;">
            <div style="font-size: 16px; color: #4f46e5; font-weight: 600; text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 10px;">Total Consumption</div>
            <div style="font-size: 56px; font-weight: 700; color: #4338ca; margin: 15px 0;">${totalConsumption.toFixed(1)}</div>
            <div style="font-size: 20px; color: #4f46e5; font-weight: 500;">Liters</div>
            <div style="margin-top: 15px; padding-top: 15px; border-top: 2px solid #c7d2fe;">
              <div style="font-size: 14px; color: #6366f1;">Across ${devices.length} device${devices.length !== 1 ? 's' : ''}</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Complete Device Analysis</h2>
            ${devices.length > 0 ? devices.map((deviceId, index) => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              const colors = ['#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#06b6d4'];
              const color = colors[index % colors.length];
              return `
              <div style="background-color: #f8fafc; border-radius: 12px; padding: 25px; margin-bottom: 18px; border-left: 5px solid ${color}; box-shadow: 0 2px 4px rgba(0,0,0,0.05);">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                  <div style="flex: 1;">
                    <div style="display: flex; align-items: center; margin-bottom: 6px;">
                      <div style="width: 12px; height: 12px; background-color: ${color}; border-radius: 50%; margin-right: 10px;"></div>
                      <div style="font-size: 18px; font-weight: 600; color: #1e293b;">${deviceName}</div>
                    </div>
                    <div style="font-size: 13px; color: #64748b; margin-left: 22px;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 32px; font-weight: 700; color: ${color};">${liters.toFixed(1)}</div>
                    <div style="font-size: 13px; color: #64748b; margin-top: 4px;">Liters</div>
                  </div>
                </div>
                <div style="background-color: #e0e7ff; border-radius: 10px; height: 12px; overflow: hidden; margin-bottom: 8px;">
                  <div style="background: linear-gradient(90deg, ${color}, ${color}dd); height: 100%; width: ${percentage}%; border-radius: 10px; transition: width 0.3s ease;"></div>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                  <div style="font-size: 13px; color: #64748b; font-weight: 500;">${percentage}% of total consumption</div>
                  <div style="font-size: 13px; color: ${color}; font-weight: 600;">Rank #${index + 1}</div>
                </div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 30px; background-color: #f8fafc; border-radius: 10px;">No consumption data available.</p>'}
          </div>

          <!-- Additional Info -->
          <div style="background: linear-gradient(135deg, #f8fafc, #f1f5f9); padding: 25px 30px; margin: 0 30px 30px 30px; border-radius: 10px; border: 1px solid #e2e8f0;">
            <div style="font-size: 14px; color: #475569; line-height: 1.8;">
              <p style="margin: 0 0 10px 0;"><strong>📌 Report Period:</strong> ${data.period || 'All Time'}</p>
              <p style="margin: 0 0 10px 0;"><strong>📅 Generated:</strong> ${new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}</p>
              <p style="margin: 0;"><strong>⏰ Time:</strong> ${new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</p>
            </div>
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This comprehensive report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #6366f1; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">For detailed analysis, please refer to the attached PDF document.</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Comprehensive Report Template (for PDF reports with leaks, manual activities, etc.)
  comprehensiveReport: (data) => {
    const deviceCount = data.deviceCount || 0;
    const totalLeaks = data.totalLeaks || 0;
    const totalManual = data.totalManual || 0;
    const period = data.period || 'All Time';
    const generatedAt = data.generatedAt || new Date().toLocaleString();
    const consumptionData = data.consumption || {};
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const devices = Object.keys(consumptionData);
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>SmartPipe Comprehensive Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📑</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">SmartPipe Report</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${period}</p>
          </div>

          <!-- Key Metrics Grid -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #eef2ff, #e0e7ff); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #818cf8;">
              <div style="font-size: 12px; color: #4f46e5; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Devices</div>
              <div style="font-size: 36px; font-weight: 700; color: #4338ca; margin: 10px 0;">${deviceCount}</div>
              <div style="font-size: 14px; color: #6366f1; font-weight: 500;">Active</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef2f2, #fee2e2); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fca5a5;">
              <div style="font-size: 12px; color: #dc2626; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Leak Events</div>
              <div style="font-size: 36px; font-weight: 700; color: #b91c1c; margin: 10px 0;">${totalLeaks}</div>
              <div style="font-size: 14px; color: #dc2626; font-weight: 500;">Detected</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 12px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Manual Switches</div>
              <div style="font-size: 36px; font-weight: 700; color: #b45309; margin: 10px 0;">${totalManual}</div>
              <div style="font-size: 14px; color: #d97706; font-weight: 500;">Triggered</div>
            </div>
          </div>

          ${totalConsumption > 0 ? `
          <!-- Water Consumption Summary -->
          <div style="padding: 0 30px 20px 30px;">
            <div style="background: linear-gradient(135deg, #ecfeff, #cffafe); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #06b6d4;">
              <div style="font-size: 14px; color: #0891b2; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Water Consumption</div>
              <div style="font-size: 42px; font-weight: 700; color: #0e7490; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 18px; color: #0891b2; font-weight: 500;">Liters</div>
            </div>
          </div>
          ` : ''}

          <!-- Report Summary -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Report Summary</h2>
            <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; border-left: 4px solid #6366f1;">
              ${data.message ? `
                <div style="color: #475569; font-size: 15px; line-height: 1.8;">
                  ${data.message.replace(/<p>/g, '<p style="margin: 0 0 12px 0;">').replace(/<strong>/g, '<strong style="color: #1e293b;">')}
                </div>
              ` : `
                <p style="color: #475569; font-size: 15px; margin: 0 0 12px 0;">
                  This comprehensive report includes detailed information about water quality, consumption, leak events, and manual switch activities for all monitored devices.
                </p>
                <p style="color: #475569; font-size: 15px; margin: 0;">
                  Please review the attached PDF document for complete details and analysis.
                </p>
              `}
            </div>
          </div>

          ${devices.length > 0 && totalConsumption > 0 ? `
          <!-- Device Consumption Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">💧 Device Consumption</h2>
            ${devices.map((deviceId, index) => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              const colors = ['#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#06b6d4'];
              const color = colors[index % colors.length];
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 18px; margin-bottom: 12px; border-left: 4px solid ${color};">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                  <div style="flex: 1;">
                    <div style="font-size: 15px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: ${color};">${liters.toFixed(1)}</div>
                    <div style="font-size: 12px; color: #64748b;">Liters</div>
                  </div>
                </div>
                <div style="background-color: #e0e7ff; border-radius: 8px; height: 8px; overflow: hidden; margin-top: 10px;">
                  <div style="background: linear-gradient(90deg, ${color}, ${color}dd); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of total</div>
              </div>
              `;
            }).join('')}
          </div>
          ` : ''}

          <!-- Additional Info -->
          <div style="background: linear-gradient(135deg, #f8fafc, #f1f5f9); padding: 25px 30px; margin: 0 30px 30px 30px; border-radius: 10px; border: 1px solid #e2e8f0;">
            <div style="font-size: 14px; color: #475569; line-height: 1.8;">
              <p style="margin: 0 0 10px 0;"><strong style="color: #1e293b;">📌 Report Period:</strong> ${period}</p>
              <p style="margin: 0 0 10px 0;"><strong style="color: #1e293b;">📅 Generated:</strong> ${new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}</p>
              <p style="margin: 0;"><strong style="color: #1e293b;">⏰ Time:</strong> ${new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</p>
            </div>
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This comprehensive report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #6366f1; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">For detailed analysis, please refer to the attached PDF document.</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${generatedAt}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  }
};

module.exports = emailTemplates;

