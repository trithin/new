import { api, ensureAuth } from './api.js';

ensureAuth();

const categoryFilter = document.getElementById('category-filter');
const soldFilter = document.getElementById('sold-filter');
const categorySelect = document.getElementById('category_id');
const listTable = document.getElementById('accounts-table');
const form = document.getElementById('account-form');
const bulkForm = document.getElementById('bulk-form');

async function loadCategories() {
  const categories = await api('/categories/');
  const options = categories.map((c) => `<option value='${c.id}'>${c.emoji} ${c.name}</option>`).join('');
  categoryFilter.innerHTML = `<option value=''>Tất cả</option>${options}`;
  categorySelect.innerHTML = options;
  document.getElementById('bulk_category_id').innerHTML = options;
}

async function loadAccounts() {
  const q = new URLSearchParams();
  if (categoryFilter.value) q.set('category_id', categoryFilter.value);
  if (soldFilter.value) q.set('sold', soldFilter.value);

  const data = await api(`/accounts/${q.toString() ? `?${q.toString()}` : ''}`);
  listTable.innerHTML = data.map((a) => `
    <tr>
      <td>${a.id}</td>
      <td>${a.category_emoji || '🔑'} ${a.category_name || ''}</td>
      <td>${a.username}</td>
      <td>${a.password}</td>
      <td>${a.extra_info || ''}</td>
      <td>${a.is_sold ? 'Đã bán' : 'Còn'}</td>
      <td>${a.is_sold ? '' : `<button class='danger' data-action='delete' data-id='${a.id}'>Xóa</button>`}</td>
    </tr>
  `).join('');
}

listTable.addEventListener('click', async (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  if (target.dataset.action !== 'delete') return;

  const id = target.dataset.id;
  if (!id) return;
  if (!confirm('Xóa tài khoản chưa bán này?')) return;

  try {
    await api(`/accounts/${id}`, { method: 'DELETE' });
    await loadAccounts();
  } catch (e) {
    alert(e.message);
  }
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    await api('/accounts/', {
      method: 'POST',
      body: JSON.stringify({
        category_id: Number(categorySelect.value),
        username: form.username.value,
        password: form.password.value,
        extra_info: form.extra_info.value,
      }),
    });
    form.reset();
    await loadAccounts();
  } catch (err) {
    alert(err.message);
  }
});

bulkForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const lines = bulkForm.lines.value
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);

  try {
    const result = await api('/accounts/bulk', {
      method: 'POST',
      body: JSON.stringify({
        category_id: Number(bulkForm.bulk_category_id.value),
        lines,
      }),
    });
    alert(`Đã thêm ${result.inserted} tài khoản`);
    bulkForm.lines.value = '';
    await loadAccounts();
  } catch (err) {
    alert(err.message);
  }
});

categoryFilter.addEventListener('change', loadAccounts);
soldFilter.addEventListener('change', loadAccounts);

await loadCategories();
await loadAccounts();
