import { api, ensureAuth, formatMoney } from './api.js';

ensureAuth();

const table = document.getElementById('users-table');
const searchInput = document.getElementById('search');
const modal = document.getElementById('modal');
const form = document.getElementById('add-balance-form');
const closeBtn = document.getElementById('close-modal');
let users = [];
let selectedId = null;

function render() {
  const keyword = searchInput.value.trim().toLowerCase();
  const filtered = users.filter((u) =>
    `${u.telegram_id}`.includes(keyword) ||
    (u.full_name || '').toLowerCase().includes(keyword),
  );

  table.innerHTML = filtered.map((u) => `
    <tr>
      <td>${u.id}</td>
      <td>${u.telegram_id}</td>
      <td>${u.full_name || ''}</td>
      <td>${u.username || ''}</td>
      <td>${formatMoney(u.balance)}</td>
      <td>${u.created_at || ''}</td>
      <td><button onclick='window.openAddBalance(${u.id})'>Nạp tiền</button></td>
    </tr>
  `).join('');
}

window.openAddBalance = (id) => {
  selectedId = id;
  form.amount.value = '';
  modal.style.display = 'flex';
};

closeBtn.addEventListener('click', () => {
  modal.style.display = 'none';
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    await api(`/users/${selectedId}/add-balance`, {
      method: 'POST',
      body: JSON.stringify({ amount: Number(form.amount.value) }),
    });
    modal.style.display = 'none';
    await load();
  } catch (err) {
    alert(err.message);
  }
});

searchInput.addEventListener('input', render);

async function load() {
  users = await api('/users/');
  render();
}

load();
