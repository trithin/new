import { api, ensureAuth, formatMoney } from './api.js';

ensureAuth();

const statUsers = document.getElementById('stat-users');
const statRevenue = document.getElementById('stat-revenue');
const statRemain = document.getElementById('stat-remain');
const statSold = document.getElementById('stat-sold');
const txTable = document.getElementById('tx-table');

async function load() {
  try {
    const data = await api('/stats');
    statUsers.textContent = data.total_users;
    statRevenue.textContent = formatMoney(data.total_revenue);
    statRemain.textContent = data.remaining_accounts;
    statSold.textContent = data.sold_accounts;

    txTable.innerHTML = (data.recent_transactions || []).map((t) => `
      <tr>
        <td>${t.id}</td>
        <td>${t.type}</td>
        <td>${formatMoney(t.amount)}</td>
        <td>${t.full_name || ''} (${t.telegram_id || ''})</td>
        <td>${t.description || ''}</td>
        <td>${t.created_at || ''}</td>
      </tr>
    `).join('');
  } catch (e) {
    alert(e.message);
  }
}

load();
