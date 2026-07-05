/* ==========================================================================
   AI Civic Guardian - Client-side app
   All data persists in localStorage in the browser. There is no backend
   server here, so this is a fully self-contained demo/MVP: open index.html
   and everything (accounts, complaints, images, tracking) works offline
   except the map tiles and optional reverse-geocoding, which need internet.

   IMPORTANT: passwords are stored in localStorage as plain text for this
   client-only demo. That is fine for local testing but is NOT secure for
   a real deployment - a real app needs a backend that hashes passwords
   (see the FastAPI backend built earlier in this conversation).
   ========================================================================== */

(function () {
  'use strict';

  // ------------------------------------------------------------------------
  // CONSTANTS
  // ------------------------------------------------------------------------

  const CATEGORIES = [
    'Potholes', 'Garbage Dump', 'Water Leakage', 'Sewage Overflow',
    'Broken Streetlight', 'Illegal Dumping', 'Traffic Signal Damage',
    'Road Damage', 'Drainage Blockage', 'Tree Fallen', 'Public Toilet Issues',
    'Stray Animals', 'Flooding', 'Pollution', 'Noise Pollution',
    'Encroachment', 'Park Maintenance', 'Electricity Problems',
    'Drinking Water Problems', 'Road Accident Spot', 'Public Property Damage',
    'Illegal Construction', 'Fire Hazard', 'Other Issues',
  ];

  const DEPARTMENT_MAP = {
    'Potholes': 'Roads Department', 'Road Damage': 'Roads Department',
    'Road Accident Spot': 'Roads Department', 'Garbage Dump': 'Sanitation Department',
    'Illegal Dumping': 'Sanitation Department', 'Water Leakage': 'Water Supply Department',
    'Drinking Water Problems': 'Water Supply Department', 'Sewage Overflow': 'Municipality',
    'Drainage Blockage': 'Municipality', 'Flooding': 'Municipality',
    'Broken Streetlight': 'Electricity Board', 'Electricity Problems': 'Electricity Board',
    'Traffic Signal Damage': 'Police Department', 'Encroachment': 'Police Department',
    'Illegal Construction': 'Corporation', 'Public Toilet Issues': 'Corporation',
    'Park Maintenance': 'Corporation', 'Tree Fallen': 'Forest Department',
    'Fire Hazard': 'Fire Department', 'Stray Animals': 'Municipality',
    'Pollution': 'Municipality', 'Noise Pollution': 'Police Department',
    'Public Property Damage': 'Corporation',
  };

  const STAGES = ['Submitted', 'Verified', 'Assigned', 'In Progress', 'Resolved', 'Closed'];

  const DEFAULT_CENTER = [11.0168, 76.9558]; // Coimbatore - sensible default map center

  const STORAGE_KEYS = {
    users: 'acg_users',
    complaints: 'acg_complaints',
    session: 'acg_session',
    theme: 'acg_theme',
  };

  // ------------------------------------------------------------------------
  // STORAGE HELPERS
  // ------------------------------------------------------------------------

  function loadJSON(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) {
      console.error('Failed to parse localStorage key', key, e);
      return fallback;
    }
  }

  function saveJSON(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
  }

  function getUsers() { return loadJSON(STORAGE_KEYS.users, []); }
  function saveUsers(users) { saveJSON(STORAGE_KEYS.users, users); }
  function getComplaints() { return loadJSON(STORAGE_KEYS.complaints, []); }
  function saveComplaints(complaints) { saveJSON(STORAGE_KEYS.complaints, complaints); }

  function uid(prefix) {
    return prefix + '_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 8);
  }

  // ------------------------------------------------------------------------
  // TOAST
  // ------------------------------------------------------------------------

  let toastTimer = null;
  function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 3000);
  }

  // ------------------------------------------------------------------------
  // AUTH
  // ------------------------------------------------------------------------

  let currentUser = null; // { id, name, email, phone, role, points, createdAt }

  function registerUser(name, email, phone, password) {
    const users = getUsers();
    if (users.some((u) => u.email.toLowerCase() === email.toLowerCase())) {
      throw new Error('An account with this email already exists');
    }
    const newUser = {
      id: uid('user'),
      name: name,
      email: email,
      phone: phone || null,
      password: password, // demo-only plain text, see file header note
      role: 'citizen',
      points: 0,
      createdAt: new Date().toISOString(),
    };
    users.push(newUser);
    saveUsers(users);
    return newUser;
  }

  function loginUser(email, password) {
    const users = getUsers();
    const user = users.find((u) => u.email.toLowerCase() === email.toLowerCase());
    if (!user || user.password !== password) {
      throw new Error('Incorrect email or password');
    }
    return user;
  }

  function persistSession(userId) {
    localStorage.setItem(STORAGE_KEYS.session, userId);
  }

  function clearSession() {
    localStorage.removeItem(STORAGE_KEYS.session);
  }

  // ------------------------------------------------------------------------
  // COMPLAINTS
  // ------------------------------------------------------------------------

  function departmentForCategory(category) {
    return DEPARTMENT_MAP[category] || 'Municipality';
  }

  function createComplaint(data) {
    const now = new Date().toISOString();
    const complaint = {
      id: uid('complaint'),
      title: data.title,
      description: data.description,
      category: data.category,
      severity: data.severity,
      status: 'Submitted',
      latitude: data.latitude,
      longitude: data.longitude,
      address: data.address || null,
      landmark: data.landmark || null,
      isAnonymous: data.isAnonymous,
      contactNumber: data.contactNumber || null,
      imageDataUrls: data.imageDataUrls || [],
      reportedBy: currentUser.id,
      department: departmentForCategory(data.category),
      statusHistory: [{ status: 'Submitted', note: 'Complaint received', timestamp: now }],
      createdAt: now,
      updatedAt: now,
    };
    const complaints = getComplaints();
    complaints.unshift(complaint);
    saveComplaints(complaints);

    // Award civic points, same rule as the backend (+10 per report)
    const users = getUsers();
    const userIndex = users.findIndex((u) => u.id === currentUser.id);
    if (userIndex !== -1) {
      users[userIndex].points = (users[userIndex].points || 0) + 10;
      saveUsers(users);
      currentUser = users[userIndex];
    }
    return complaint;
  }

  function advanceComplaintStage(complaintId) {
    const complaints = getComplaints();
    const index = complaints.findIndex((c) => c.id === complaintId);
    if (index === -1) return null;

    const complaint = complaints[index];
    const currentStageIndex = STAGES.indexOf(complaint.status);
    const nextStageIndex = Math.min(currentStageIndex + 1, STAGES.length - 1);
    const nextStage = STAGES[nextStageIndex];

    if (nextStage !== complaint.status) {
      complaint.status = nextStage;
      complaint.updatedAt = new Date().toISOString();
      complaint.statusHistory.push({
        status: nextStage,
        note: nextStage === 'Resolved' ? 'Issue has been resolved by the department' : `Status updated to ${nextStage}`,
        timestamp: complaint.updatedAt,
      });
      complaints[index] = complaint;
      saveComplaints(complaints);
    }
    return complaint;
  }

  function dashboardStatsFor(userId) {
    const mine = getComplaints().filter((c) => c.reportedBy === userId);
    return {
      total: mine.length,
      resolved: mine.filter((c) => c.status === 'Resolved' || c.status === 'Closed').length,
      pending: mine.filter((c) => ['Submitted', 'Verified', 'Assigned'].includes(c.status)).length,
      inProgress: mine.filter((c) => c.status === 'In Progress').length,
    };
  }

  // ------------------------------------------------------------------------
  // UI: SCREEN / TAB SWITCHING
  // ------------------------------------------------------------------------

  function showScreen(screenId) {
    document.querySelectorAll('.screen').forEach((el) => el.classList.remove('active'));
    document.getElementById(screenId).classList.add('active');
  }

  function showAppTab(tabName) {
    document.querySelectorAll('.tab-page').forEach((el) => el.classList.remove('active'));
    document.getElementById('tab-' + tabName).classList.add('active');
    document.querySelectorAll('.nav-btn').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === tabName);
    });

    if (tabName === 'home') renderHomeTab();
    if (tabName === 'map') renderMapTab();
    if (tabName === 'tracking') renderTrackingTab();
    if (tabName === 'profile') renderProfileTab();
  }

  // ------------------------------------------------------------------------
  // RENDER: HOME TAB
  // ------------------------------------------------------------------------

  function statusChipHTML(status) {
    const cssClass = 'status-' + status.replace(/\s+/g, '-');
    return `<span class="status-chip ${cssClass}">${status}</span>`;
  }

  function complaintCardHTML(complaint) {
    const thumbStyle = complaint.imageDataUrls.length > 0
      ? `style="background-image:url('${complaint.imageDataUrls[0]}')"`
      : '';
    const thumbContent = complaint.imageDataUrls.length > 0 ? '' : '📍';
    return `
      <div class="complaint-card" data-id="${complaint.id}">
        <div class="complaint-thumb" ${thumbStyle}>${thumbContent}</div>
        <div class="complaint-info">
          <div class="title">${escapeHTML(complaint.title)}</div>
          <div class="meta">${escapeHTML(complaint.category)} • ${escapeHTML(complaint.severity)}</div>
        </div>
        ${statusChipHTML(complaint.status)}
      </div>
    `;
  }

  function escapeHTML(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  function renderHomeTab() {
    document.getElementById('greeting').textContent = 'Hi, ' + (currentUser.name.split(' ')[0] || 'Citizen');
    document.getElementById('pointsDisplay').textContent = currentUser.points || 0;

    const stats = dashboardStatsFor(currentUser.id);
    document.getElementById('statTotal').textContent = stats.total;
    document.getElementById('statResolved').textContent = stats.resolved;
    document.getElementById('statPending').textContent = stats.pending;
    document.getElementById('statInProgress').textContent = stats.inProgress;

    const mine = getComplaints().filter((c) => c.reportedBy === currentUser.id).slice(0, 5);
    const recentList = document.getElementById('recentList');
    recentList.innerHTML = mine.length
      ? mine.map(complaintCardHTML).join('')
      : '<div class="empty-msg">No complaints yet. Tap Report to submit one!</div>';

    recentList.querySelectorAll('.complaint-card').forEach((card) => {
      card.addEventListener('click', () => openDetailModal(card.dataset.id));
    });
  }

  // ------------------------------------------------------------------------
  // REPORT TAB
  // ------------------------------------------------------------------------

  let capturedLatitude = null;
  let capturedLongitude = null;
  let capturedAddress = null;
  let photoDataUrls = [];

  function populateCategoryDropdowns() {
    const reportSelect = document.getElementById('reportCategory');
    reportSelect.innerHTML = CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('');

    const mapSelect = document.getElementById('mapCategoryFilter');
    mapSelect.innerHTML =
      '<option value="">All Categories</option>' +
      CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('');
  }

  function captureLocation() {
    const btn = document.getElementById('captureLocationBtn');
    const textEl = document.getElementById('locationText');

    if (!navigator.geolocation) {
      showToast('Geolocation is not supported by this browser');
      return;
    }

    btn.disabled = true;
    btn.textContent = 'Locating...';

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        capturedLatitude = position.coords.latitude;
        capturedLongitude = position.coords.longitude;
        capturedAddress = null;

        textEl.textContent = `${capturedLatitude.toFixed(5)}, ${capturedLongitude.toFixed(5)}`;

        // Best-effort reverse geocoding via OpenStreetMap Nominatim (free, no API key).
        // This is optional - if it fails or there's no internet, GPS coordinates are
        // still captured and the complaint can still be submitted.
        try {
          const response = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${capturedLatitude}&lon=${capturedLongitude}`
          );
          if (response.ok) {
            const data = await response.json();
            if (data && data.display_name) {
              capturedAddress = data.display_name;
              textEl.textContent = capturedAddress;
            }
          }
        } catch (e) {
          // Silent fallback to raw coordinates - this is expected if offline.
        }

        btn.disabled = false;
        btn.textContent = 'Update';
      },
      (error) => {
        btn.disabled = false;
        btn.textContent = 'Capture GPS';
        showToast('Could not get location: ' + error.message);
      },
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  function renderPhotoPreview() {
    const container = document.getElementById('photoPreview');
    container.innerHTML = photoDataUrls
      .map(
        (url, index) => `
        <div class="photo-thumb">
          <img src="${url}" alt="photo ${index + 1}">
          <button type="button" class="remove-btn" data-index="${index}">✕</button>
        </div>`
      )
      .join('');

    container.querySelectorAll('.remove-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        photoDataUrls.splice(Number(btn.dataset.index), 1);
        renderPhotoPreview();
      });
    });
  }

  function handlePhotoInput(event) {
    const files = Array.from(event.target.files || []);
    const remainingSlots = 5 - photoDataUrls.length;
    if (remainingSlots <= 0) {
      showToast('Maximum 5 images allowed');
      event.target.value = '';
      return;
    }

    const filesToAdd = files.slice(0, remainingSlots);
    let processed = 0;
    filesToAdd.forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        photoDataUrls.push(reader.result);
        processed++;
        if (processed === filesToAdd.length) renderPhotoPreview();
      };
      reader.readAsDataURL(file);
    });

    event.target.value = ''; // allow re-selecting the same file later
  }

  function resetReportForm() {
    document.getElementById('reportForm').reset();
    capturedLatitude = null;
    capturedLongitude = null;
    capturedAddress = null;
    photoDataUrls = [];
    renderPhotoPreview();
    document.getElementById('locationText').textContent = 'Location not captured yet';
    document.getElementById('contactField').style.display = 'block';
    document.getElementById('reportError').textContent = '';
  }

  function handleReportSubmit(event) {
    event.preventDefault();
    const errorEl = document.getElementById('reportError');
    errorEl.textContent = '';

    if (capturedLatitude === null || capturedLongitude === null) {
      errorEl.textContent = 'Please capture your location before submitting';
      return;
    }

    createComplaint({
      title: document.getElementById('reportTitle').value.trim(),
      description: document.getElementById('reportDescription').value.trim(),
      category: document.getElementById('reportCategory').value,
      severity: document.getElementById('reportSeverity').value,
      latitude: capturedLatitude,
      longitude: capturedLongitude,
      address: capturedAddress,
      landmark: document.getElementById('reportLandmark').value.trim() || null,
      isAnonymous: document.getElementById('reportAnonymous').checked,
      contactNumber: document.getElementById('reportContact').value.trim() || null,
      imageDataUrls: photoDataUrls,
    });

    showToast('Complaint submitted successfully! +10 civic points 🎉');
    resetReportForm();
    showAppTab('home');
  }

  // ------------------------------------------------------------------------
  // MAP TAB
  // ------------------------------------------------------------------------

  let leafletMap = null;
  let markerLayer = null;

  function severityColor(severity) {
    switch (severity) {
      case 'Critical': return '#C62828';
      case 'High': return '#E65100';
      case 'Medium': return '#F9A825';
      default: return '#2E7D32';
    }
  }

  function initMapIfNeeded() {
    if (leafletMap) return;
    leafletMap = L.map('mapView').setView(DEFAULT_CENTER, 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19,
    }).addTo(leafletMap);
    markerLayer = L.layerGroup().addTo(leafletMap);
  }

  function renderMapTab() {
    initMapIfNeeded();
    // Leaflet needs a nudge to size correctly the first time its container becomes visible.
    setTimeout(() => leafletMap.invalidateSize(), 50);

    const categoryFilter = document.getElementById('mapCategoryFilter').value;
    const complaints = getComplaints().filter((c) => !categoryFilter || c.category === categoryFilter);

    markerLayer.clearLayers();
    complaints.forEach((c) => {
      const marker = L.circleMarker([c.latitude, c.longitude], {
        radius: 9,
        color: '#fff',
        weight: 2,
        fillColor: severityColor(c.severity),
        fillOpacity: 0.9,
      });
      marker.bindPopup(
        `<strong>${escapeHTML(c.title)}</strong><br>${escapeHTML(c.category)} - ${escapeHTML(c.status)}<br><a href="#" data-id="${c.id}" class="popup-link">View details</a>`
      );
      marker.on('popupopen', () => {
        const link = document.querySelector('.leaflet-popup .popup-link');
        if (link) {
          link.addEventListener('click', (e) => {
            e.preventDefault();
            openDetailModal(c.id);
          });
        }
      });
      marker.addTo(markerLayer);
    });
  }

  // ------------------------------------------------------------------------
  // TRACKING TAB
  // ------------------------------------------------------------------------

  let trackingMode = 'mine'; // 'mine' | 'all'

  function renderTrackingTab() {
    const complaints = trackingMode === 'mine'
      ? getComplaints().filter((c) => c.reportedBy === currentUser.id)
      : getComplaints();

    const listEl = document.getElementById('trackingList');
    listEl.innerHTML = complaints.length
      ? complaints.map(complaintCardHTML).join('')
      : '<div class="empty-msg">No complaints found</div>';

    listEl.querySelectorAll('.complaint-card').forEach((card) => {
      card.addEventListener('click', () => openDetailModal(card.dataset.id));
    });
  }

  // ------------------------------------------------------------------------
  // DETAIL MODAL
  // ------------------------------------------------------------------------

  function openDetailModal(complaintId) {
    const complaint = getComplaints().find((c) => c.id === complaintId);
    if (!complaint) return;

    const currentStageIndex = Math.max(0, STAGES.indexOf(complaint.status));

    const imagesHTML = complaint.imageDataUrls.length
      ? `<div class="detail-images">${complaint.imageDataUrls.map((url) => `<img src="${url}">`).join('')}</div>`
      : '';

    const timelineHTML = STAGES.map((stage, index) => {
      const isDone = index <= currentStageIndex;
      const historyEntry = complaint.statusHistory.find((h) => h.status === stage);
      const timeHTML = historyEntry
        ? `<div class="stage-time">${new Date(historyEntry.timestamp).toLocaleString()}${historyEntry.note ? ' • ' + escapeHTML(historyEntry.note) : ''}</div>`
        : '';
      return `
        <div class="timeline-item">
          <div class="timeline-marker">
            <div class="timeline-dot ${isDone ? 'done' : ''}">${isDone ? '✓' : ''}</div>
            ${index !== STAGES.length - 1 ? `<div class="timeline-line ${index < currentStageIndex ? 'done' : ''}"></div>` : ''}
          </div>
          <div class="timeline-content">
            <div class="stage-name">${stage}</div>
            ${timeHTML}
          </div>
        </div>`;
    }).join('');

    const canAdvance = complaint.status !== 'Closed';
    const advanceButtonHTML = canAdvance
      ? `<button id="advanceStageBtn" class="btn-secondary" style="width:100%; margin-top:14px;" data-id="${complaint.id}">
           Simulate Next Stage (demo - normally done by an officer)
         </button>`
      : '';

    document.getElementById('detailContent').innerHTML = `
      ${imagesHTML}
      <h3 style="margin:0 0 6px;">${escapeHTML(complaint.title)}</h3>
      <div class="detail-tags">
        <span class="tag">${escapeHTML(complaint.category)}</span>
        <span class="tag">${escapeHTML(complaint.severity)}</span>
        <span class="tag">${escapeHTML(complaint.department)}</span>
      </div>
      <p style="font-size:14px; line-height:1.5;">${escapeHTML(complaint.description)}</p>
      ${complaint.address ? `<p style="font-size:13px; color:var(--muted);">📍 ${escapeHTML(complaint.address)}</p>` : ''}
      <h4 style="margin:20px 0 10px;">Progress Timeline</h4>
      <div class="timeline">${timelineHTML}</div>
      ${advanceButtonHTML}
    `;

    const advanceBtn = document.getElementById('advanceStageBtn');
    if (advanceBtn) {
      advanceBtn.addEventListener('click', () => {
        advanceComplaintStage(complaint.id);
        openDetailModal(complaint.id); // re-render with updated timeline
        renderHomeTab();
        renderTrackingTab();
      });
    }

    document.getElementById('detailModal').classList.add('active');
  }

  function closeDetailModal() {
    document.getElementById('detailModal').classList.remove('active');
  }

  // ------------------------------------------------------------------------
  // PROFILE TAB
  // ------------------------------------------------------------------------

  function renderProfileTab() {
    document.getElementById('profileAvatar').textContent = (currentUser.name[0] || '?').toUpperCase();
    document.getElementById('profileName').textContent = currentUser.name;
    document.getElementById('profileEmail').textContent = currentUser.email;
    document.getElementById('profilePoints').textContent = currentUser.points || 0;
    document.getElementById('profileRole').textContent = currentUser.role;

    const phoneRow = document.getElementById('profilePhoneRow');
    if (currentUser.phone) {
      phoneRow.style.display = 'flex';
      document.getElementById('profilePhone').textContent = currentUser.phone;
    } else {
      phoneRow.style.display = 'none';
    }

    document.getElementById('themeLabel').textContent =
      document.body.classList.contains('dark') ? 'Dark' : 'Light';
  }

  // ------------------------------------------------------------------------
  // THEME
  // ------------------------------------------------------------------------

  function applySavedTheme() {
    const saved = localStorage.getItem(STORAGE_KEYS.theme);
    if (saved === 'dark') document.body.classList.add('dark');
  }

  function toggleTheme() {
    document.body.classList.toggle('dark');
    localStorage.setItem(STORAGE_KEYS.theme, document.body.classList.contains('dark') ? 'dark' : 'light');
    renderProfileTab();
  }

  // ------------------------------------------------------------------------
  // LOGOUT / LOGIN FLOW
  // ------------------------------------------------------------------------

  function enterApp() {
    showScreen('appScreen');
    showAppTab('home');
  }

  function logout() {
    clearSession();
    currentUser = null;
    showScreen('authScreen');
  }

  function tryAutoLogin() {
    const savedUserId = localStorage.getItem(STORAGE_KEYS.session);
    if (!savedUserId) {
      showScreen('authScreen');
      return;
    }
    const users = getUsers();
    const user = users.find((u) => u.id === savedUserId);
    if (user) {
      currentUser = user;
      enterApp();
    } else {
      clearSession();
      showScreen('authScreen');
    }
  }

  // ------------------------------------------------------------------------
  // EVENT WIRING
  // ------------------------------------------------------------------------

  function wireAuthScreen() {
    document.querySelectorAll('.tab-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));
        document.querySelectorAll('.tab-pane').forEach((p) => p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(btn.dataset.tab + 'Form').classList.add('active');
      });
    });

    document.getElementById('loginForm').addEventListener('submit', (event) => {
      event.preventDefault();
      const errorEl = document.getElementById('loginError');
      errorEl.textContent = '';
      try {
        const email = document.getElementById('loginEmail').value.trim();
        const password = document.getElementById('loginPassword').value;
        const user = loginUser(email, password);
        currentUser = user;
        persistSession(user.id);
        document.getElementById('loginForm').reset();
        enterApp();
      } catch (e) {
        errorEl.textContent = e.message;
      }
    });

    document.getElementById('registerForm').addEventListener('submit', (event) => {
      event.preventDefault();
      const errorEl = document.getElementById('registerError');
      errorEl.textContent = '';
      try {
        const name = document.getElementById('registerName').value.trim();
        const email = document.getElementById('registerEmail').value.trim();
        const phone = document.getElementById('registerPhone').value.trim();
        const password = document.getElementById('registerPassword').value;

        if (name.length < 2) throw new Error('Enter your full name');
        if (password.length < 6) throw new Error('Password must be at least 6 characters');

        registerUser(name, email, phone, password);
        showToast('Account created! Please sign in.');
        document.getElementById('registerForm').reset();
        document.querySelector('.tab-btn[data-tab="login"]').click();
      } catch (e) {
        errorEl.textContent = e.message;
      }
    });
  }

  function wireAppShell() {
    document.querySelectorAll('.nav-btn').forEach((btn) => {
      btn.addEventListener('click', () => showAppTab(btn.dataset.tab));
    });
    document.getElementById('logoutBtn').addEventListener('click', logout);
    document.getElementById('logoutBtn2').addEventListener('click', logout);
    document.getElementById('themeToggleBtn').addEventListener('click', toggleTheme);
  }

  function wireReportForm() {
    document.getElementById('reportForm').addEventListener('submit', handleReportSubmit);
    document.getElementById('captureLocationBtn').addEventListener('click', captureLocation);
    document.getElementById('photoInput').addEventListener('change', handlePhotoInput);
    document.getElementById('reportAnonymous').addEventListener('change', (event) => {
      document.getElementById('contactField').style.display = event.target.checked ? 'none' : 'block';
    });
  }

  function wireMapFilter() {
    document.getElementById('mapCategoryFilter').addEventListener('change', renderMapTab);
  }

  function wireTrackingSegment() {
    document.querySelectorAll('#trackingSegment .segment-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('#trackingSegment .segment-btn').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        trackingMode = btn.dataset.value;
        renderTrackingTab();
      });
    });
  }

  function wireModal() {
    document.getElementById('closeDetailBtn').addEventListener('click', closeDetailModal);
    document.getElementById('detailModal').addEventListener('click', (event) => {
      if (event.target.id === 'detailModal') closeDetailModal();
    });
  }

  // ------------------------------------------------------------------------
  // INIT
  // ------------------------------------------------------------------------

  document.addEventListener('DOMContentLoaded', () => {
    applySavedTheme();
    populateCategoryDropdowns();
    renderPhotoPreview();

    wireAuthScreen();
    wireAppShell();
    wireReportForm();
    wireMapFilter();
    wireTrackingSegment();
    wireModal();

    tryAutoLogin();
  });
})();
