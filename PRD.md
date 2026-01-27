# Product Requirements Document: Repub Admin Panel

**Version:** 2.0
**Last Updated:** 2026-01-27
**Status:** Active Development - Admin Panel Implementation Phase
**State Management:** BLoC (flutter_bloc)

## Executive Summary

Repub is a self-hosted Dart/Flutter package registry implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md). This document focuses on the **Admin Panel implementation** using Flutter Web with BLoC state management pattern.

## Current Implementation Status

### ✅ Completed Features (v1.0)
- Core API server with package publish/download
- Bearer token authentication with scoped permissions
- SQLite/PostgreSQL database support
- Local/S3 blob storage
- Public web UI (Jaspr) for package browsing
- User registration and token management
- Admin authentication system
- Basic dashboard with analytics charts

### ✅ Completed: Admin Panel Screens (BLoC Pattern)
All admin screens have been implemented with full BLoC state management:

1. **Dashboard** ✅ (Complete - BLoC pattern, stats grid, recent activity, quick actions)
2. **Local Packages** ✅ (Complete - search, pagination, delete, discontinue)
3. **Cached Packages** ✅ (Complete - view/clear cache, storage stats)
4. **Users Management** ✅ (Complete - filter, activate/deactivate, view tokens)
5. **Admin Users** ✅ (Complete - read-only list, CLI info banner)
6. **Admin User Detail** ✅ (Complete - login history, statistics, filters)
7. **Site Configuration** ✅ (Complete - form with save/reset, grouped settings)
8. **Login** ✅ (Complete)

## Architecture: BLoC State Management

### Why BLoC for Admin Panel?

1. **Separation of Concerns**: Business logic separated from UI
2. **Testability**: Easy to unit test BLoCs independently
3. **Predictable State**: Clear state transitions
4. **Reactive Programming**: Stream-based state updates
5. **Flutter Best Practice**: Official recommendation for complex apps

### BLoC Pattern Structure

```
packages/repub_admin/lib/
├── main.dart                      # Entry point
├── app.dart                       # App widget with BLoC providers
├── router.dart                    # GoRouter configuration
├── blocs/                         # 🆕 State management
│   ├── dashboard/
│   │   ├── dashboard_bloc.dart
│   │   ├── dashboard_event.dart
│   │   └── dashboard_state.dart
│   ├── local_packages/
│   │   ├── local_packages_bloc.dart
│   │   ├── local_packages_event.dart
│   │   └── local_packages_state.dart
│   ├── cached_packages/
│   │   ├── cached_packages_bloc.dart
│   │   ├── cached_packages_event.dart
│   │   └── cached_packages_state.dart
│   ├── users/
│   │   ├── users_bloc.dart
│   │   ├── users_event.dart
│   │   └── users_state.dart
│   ├── admin_users/
│   │   ├── admin_users_bloc.dart
│   │   ├── admin_users_event.dart
│   │   └── admin_users_state.dart
│   └── config/
│       ├── config_bloc.dart
│       ├── config_event.dart
│       └── config_state.dart
├── screens/                       # UI screens
│   ├── dashboard_screen.dart
│   ├── local_packages_screen.dart
│   ├── cached_packages_screen.dart
│   ├── users_screen.dart
│   ├── admin_users_screen.dart
│   ├── admin_user_detail_screen.dart
│   ├── site_config_screen.dart
│   └── login_screen.dart
├── widgets/                       # Reusable widgets
│   ├── admin_layout.dart
│   ├── data_table_card.dart
│   ├── stat_card.dart
│   ├── loading_indicator.dart
│   └── error_view.dart
├── services/                      # API clients
│   ├── admin_api_client.dart
│   └── auth_service.dart          # Auth BLoC
└── models/                        # 🆕 Data models
    ├── package_info.dart
    ├── user_info.dart
    ├── admin_user_info.dart
    └── site_config.dart
```

## Feature Specifications

### 1. Dashboard Screen (Refactor + Enhance)

**Current State**: Has basic stats and charts but uses StatefulWidget
**Goal**: Refactor to BLoC pattern and add more metrics

#### BLoC Implementation

**DashboardBloc States**:
```dart
abstract class DashboardState extends Equatable {
  const DashboardState();
}

class DashboardInitial extends DashboardState {}

class DashboardLoading extends DashboardState {}

class DashboardLoaded extends DashboardState {
  final AdminStats stats;
  final Map<String, int> packagesCreated;
  final Map<String, int> downloads;
  final List<RecentActivity> recentActivity;  // 🆕 New feature

  const DashboardLoaded({
    required this.stats,
    required this.packagesCreated,
    required this.downloads,
    required this.recentActivity,
  });
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError(this.message);
}
```

**DashboardBloc Events**:
```dart
abstract class DashboardEvent extends Equatable {
  const DashboardEvent();
}

class DashboardLoadRequested extends DashboardEvent {}

class DashboardRefreshRequested extends DashboardEvent {}
```

#### UI Requirements

**Layout**:
- 4 stat cards (total packages, total users, downloads today, cached packages)
- 2 charts (packages created, downloads per hour)
- Recent activity feed (last 10 actions)
- Refresh button with loading indicator

**Metrics to Display**:
- Total local packages
- Total cached packages from upstream
- Total registered users
- Total admin users
- Downloads in last 24 hours
- Packages published in last 7 days
- Storage usage (packages + cache)

**Recent Activity Feed**:
- Package published (user, package name, version, timestamp)
- User registered (email, timestamp)
- Admin login (username, IP, timestamp)
- Package downloaded (package name, version, timestamp)

#### API Endpoints
- `GET /admin/api/stats` - Dashboard statistics
- `GET /admin/api/analytics/packages-created?days=30` - Chart data
- `GET /admin/api/analytics/downloads?hours=24` - Chart data
- `GET /admin/api/activity?limit=10` - Recent activity (🆕 new endpoint)

---

### 2. Local Packages Screen

**Goal**: Manage all packages published to this registry

#### BLoC Implementation

**LocalPackagesBloc States**:
```dart
abstract class LocalPackagesState extends Equatable {
  const LocalPackagesState();
}

class LocalPackagesInitial extends LocalPackagesState {}

class LocalPackagesLoading extends LocalPackagesState {}

class LocalPackagesLoaded extends LocalPackagesState {
  final List<PackageInfo> packages;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final String? searchQuery;

  const LocalPackagesLoaded({
    required this.packages,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    this.searchQuery,
  });

  bool get hasNextPage => currentPage * pageSize < totalCount;
  bool get hasPrevPage => currentPage > 1;
}

class LocalPackageDeleting extends LocalPackagesState {
  final String packageName;
  const LocalPackageDeleting(this.packageName);
}

class LocalPackageDeleted extends LocalPackagesState {
  final String packageName;
  const LocalPackageDeleted(this.packageName);
}

class LocalPackagesError extends LocalPackagesState {
  final String message;
  const LocalPackagesError(this.message);
}
```

**LocalPackagesBloc Events**:
```dart
abstract class LocalPackagesEvent extends Equatable {
  const LocalPackagesEvent();
}

class LocalPackagesLoadRequested extends LocalPackagesEvent {
  final int page;
  final String? searchQuery;
  const LocalPackagesLoadRequested({this.page = 1, this.searchQuery});
}

class LocalPackagesSearchChanged extends LocalPackagesEvent {
  final String query;
  const LocalPackagesSearchChanged(this.query);
}

class LocalPackageDeleteRequested extends LocalPackagesEvent {
  final String packageName;
  const LocalPackageDeleteRequested(this.packageName);
}

class LocalPackageDiscontinueRequested extends LocalPackagesEvent {
  final String packageName;
  final String? reason;
  final String? replacedBy;
  const LocalPackageDiscontinueRequested(this.packageName, {this.reason, this.replacedBy});
}

class LocalPackagesPageChanged extends LocalPackagesEvent {
  final int page;
  const LocalPackagesPageChanged(this.page);
}
```

#### UI Requirements

**Layout**:
- Search bar (debounced search)
- Data table with columns:
  - Package Name (clickable to pub.dev-style view)
  - Latest Version
  - Total Versions
  - Published Date
  - Publisher (user email)
  - Downloads (total)
  - Actions (View, Delete, Discontinue)
- Pagination controls
- Empty state when no packages

**Features**:
- **Search**: Filter by package name/description (debounced 500ms)
- **Sort**: By name, published date, downloads
- **Delete**: Show confirmation dialog, requires password
- **Discontinue**: Dialog with reason and replacement package fields
- **View**: Navigate to package detail page (future feature)

**Delete Confirmation**:
- Two-step process for safety
- Show package name and version count
- Require typing package name to confirm
- Cannot be undone warning
- API call: `DELETE /admin/api/packages/:name`

**Discontinue Dialog**:
- Reason for discontinuation (optional text)
- Replacement package name (optional)
- Package becomes unavailable for new installs
- Existing installs continue to work
- API call: `POST /admin/api/packages/:name/discontinue`

#### API Endpoints
- `GET /admin/api/packages/local?page=1&limit=20&search=query`
- `DELETE /admin/api/packages/:name`
- `POST /admin/api/packages/:name/discontinue`

---

### 3. Cached Packages Screen

**Goal**: View and manage cached packages from upstream (pub.dev)

#### BLoC Implementation

**CachedPackagesBloc States**:
```dart
abstract class CachedPackagesState extends Equatable {
  const CachedPackagesState();
}

class CachedPackagesInitial extends CachedPackagesState {}

class CachedPackagesLoading extends CachedPackagesState {}

class CachedPackagesLoaded extends CachedPackagesState {
  final List<PackageInfo> packages;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final String? searchQuery;
  final int totalStorageBytes;

  const CachedPackagesLoaded({
    required this.packages,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    this.searchQuery,
    required this.totalStorageBytes,
  });

  bool get hasNextPage => currentPage * pageSize < totalCount;
  bool get hasPrevPage => currentPage > 1;
}

class CachedPackageClearing extends CachedPackagesState {
  final String packageName;
  const CachedPackageClearing(this.packageName);
}

class CachedPackageCleared extends CachedPackagesState {
  final String packageName;
  const CachedPackageCleared(this.packageName);
}

class CachedPackagesClearingAll extends CachedPackagesState {}

class CachedPackagesClearedAll extends CachedPackagesState {}

class CachedPackagesError extends CachedPackagesState {
  final String message;
  const CachedPackagesError(this.message);
}
```

**CachedPackagesBloc Events**:
```dart
abstract class CachedPackagesEvent extends Equatable {
  const CachedPackagesEvent();
}

class CachedPackagesLoadRequested extends CachedPackagesEvent {
  final int page;
  final String? searchQuery;
  const CachedPackagesLoadRequested({this.page = 1, this.searchQuery});
}

class CachedPackagesSearchChanged extends CachedPackagesEvent {
  final String query;
  const CachedPackagesSearchChanged(this.query);
}

class CachedPackageClearRequested extends CachedPackagesEvent {
  final String packageName;
  const CachedPackageClearRequested(this.packageName);
}

class CachedPackagesClearAllRequested extends CachedPackagesEvent {}

class CachedPackagesPageChanged extends CachedPackagesEvent {
  final int page;
  const CachedPackagesPageChanged(this.page);
}
```

#### UI Requirements

**Layout**:
- Similar to Local Packages screen
- Different action buttons (Clear cache, not Delete)
- Show upstream source (pub.dev)
- Show cache date
- Storage size per package

**Data Table Columns**:
- Package Name
- Cached Version
- Original Source (pub.dev)
- Cache Date
- Storage Size
- Downloads from Cache
- Actions (View on pub.dev, Clear Cache)

**Features**:
- **Clear Cache**: Remove individual package from cache
- **Clear All**: Bulk clear all cached packages (with confirmation)
- **View Upstream**: Link to pub.dev package page
- **Storage Stats**: Total cache size, packages count

**Cache Clearing**:
- Individual: Confirmation dialog with size info
- Bulk: Requires typing "CLEAR ALL CACHE" to confirm
- Shows space that will be freed
- Updates storage stats after clear

#### API Endpoints
- `GET /admin/api/packages/cached?page=1&limit=20`
- `DELETE /admin/api/packages/cached/:name` - Clear individual
- `DELETE /admin/api/packages/cached` - Clear all cache

---

### 4. Users Screen

**Goal**: Manage regular users (not admin users)

#### BLoC Implementation

**UsersBloc States**:
```dart
abstract class UsersState extends Equatable {
  const UsersState();
}

class UsersInitial extends UsersState {}

class UsersLoading extends UsersState {}

class UsersLoaded extends UsersState {
  final List<UserInfo> users;
  final int totalCount;
  final int currentPage;
  final String? searchQuery;
  final UserFilter filter; // active, inactive, all

  const UsersLoaded({
    required this.users,
    required this.totalCount,
    required this.currentPage,
    this.searchQuery,
    this.filter = UserFilter.all,
  });
}

class UserUpdating extends UsersState {
  final String userId;
  const UserUpdating(this.userId);
}

class UsersError extends UsersState {
  final String message;
  const UsersError(this.message);
}

enum UserFilter { all, active, inactive }
```

**UsersBloc Events**:
```dart
abstract class UsersEvent extends Equatable {
  const UsersEvent();
}

class UsersLoadRequested extends UsersEvent {
  final int page;
  final String? searchQuery;
  final UserFilter filter;
  const UsersLoadRequested({
    this.page = 1,
    this.searchQuery,
    this.filter = UserFilter.all,
  });
}

class UserSearchChanged extends UsersEvent {
  final String query;
  const UserSearchChanged(this.query);
}

class UserFilterChanged extends UsersEvent {
  final UserFilter filter;
  const UserFilterChanged(this.filter);
}

class UserDeactivateRequested extends UsersEvent {
  final String userId;
  const UserDeactivateRequested(this.userId);
}

class UserActivateRequested extends UsersEvent {
  final String userId;
  const UserActivateRequested(this.userId);
}

class UserDeleteRequested extends UsersEvent {
  final String userId;
  const UserDeleteRequested(this.userId);
}

class UserTokensViewRequested extends UsersEvent {
  final String userId;
  const UserTokensViewRequested(this.userId);
}
```

#### UI Requirements

**Layout**:
- Filter chips: All, Active, Inactive
- Search bar (by email/name)
- User count badge per filter
- Data table with columns:
  - Email
  - Name
  - Status (Active/Inactive badge)
  - Registered Date
  - Last Login
  - Token Count
  - Package Count (owned)
  - Actions (View Tokens, Deactivate/Activate, Delete)
- Pagination

**Features**:
- **Search**: Filter by email or name
- **Filter**: Show all/active/inactive users
- **Deactivate**: Disable user (cannot login, tokens invalid)
- **Activate**: Re-enable deactivated user
- **Delete**: Permanent deletion with confirmation
- **View Tokens**: Show list of user's API tokens (read-only)

**User Actions**:
1. **Deactivate**:
   - Confirmation dialog
   - User cannot login after deactivation
   - All tokens become invalid
   - Reversible via Activate

2. **Delete**:
   - Two-step confirmation
   - Requires typing user email
   - Deletes user, tokens, and package ownership transfers
   - Cannot be undone

3. **View Tokens**:
   - Modal/dialog showing user's tokens
   - Columns: Label, Scopes, Created, Last Used, Expires
   - Admin can revoke tokens (but not view token values)

#### API Endpoints
- `GET /admin/api/users?page=1&limit=20&search=query&status=active`
- `POST /admin/api/users/:id/deactivate`
- `POST /admin/api/users/:id/activate`
- `DELETE /admin/api/users/:id`
- `GET /admin/api/users/:id/tokens` - List user tokens

---

### 5. Admin Users Screen

**Goal**: View all admin users and their login history

#### BLoC Implementation

**AdminUsersBloc States**:
```dart
abstract class AdminUsersState extends Equatable {
  const AdminUsersState();
}

class AdminUsersInitial extends AdminUsersState {}

class AdminUsersLoading extends AdminUsersState {}

class AdminUsersLoaded extends AdminUsersState {
  final List<AdminUserInfo> adminUsers;
  final AdminUserInfo? currentAdmin; // Currently logged in

  const AdminUsersLoaded({
    required this.adminUsers,
    this.currentAdmin,
  });
}

class AdminUsersError extends AdminUsersState {
  final String message;
  const AdminUsersError(this.message);
}
```

**AdminUsersBloc Events**:
```dart
abstract class AdminUsersEvent extends Equatable {
  const AdminUsersEvent();
}

class AdminUsersLoadRequested extends AdminUsersEvent {}

class AdminUserDetailRequested extends AdminUsersEvent {
  final String adminId;
  const AdminUserDetailRequested(this.adminId);
}
```

#### UI Requirements

**Layout**:
- Info banner: "Admin users can only be managed via CLI"
- Current user highlighted
- Data table with columns:
  - Username
  - Email
  - Status (Active/Inactive)
  - Created Date
  - Last Login
  - Login Count (total)
  - Failed Logins (last 30 days)
  - Actions (View Details)

**Features**:
- **Read-Only**: Cannot create/edit/delete from UI
- **Current User**: Highlighted with badge
- **View Details**: Navigate to detail page
- **Security Info**: Show CLI commands for management

**Info Banner**:
```
ℹ️ Admin users can only be managed via CLI for security reasons.
To create: repub_cli admin create <username> <password> "<name>"
To list: repub_cli admin list
```

#### API Endpoints
- `GET /admin/api/admin-users` - List all admin users
- `GET /admin/api/auth/me` - Current admin info

---

### 6. Admin User Detail Screen

**Goal**: View individual admin user's detailed information and login history

#### BLoC Implementation

**AdminUserDetailBloc States**:
```dart
abstract class AdminUserDetailState extends Equatable {
  const AdminUserDetailState();
}

class AdminUserDetailInitial extends AdminUserDetailState {}

class AdminUserDetailLoading extends AdminUserDetailState {}

class AdminUserDetailLoaded extends AdminUserDetailState {
  final AdminUserInfo adminUser;
  final List<LoginAttempt> loginHistory;
  final LoginStats stats;

  const AdminUserDetailLoaded({
    required this.adminUser,
    required this.loginHistory,
    required this.stats,
  });
}

class AdminUserDetailError extends AdminUserDetailState {
  final String message;
  const AdminUserDetailError(this.message);
}
```

**AdminUserDetailBloc Events**:
```dart
abstract class AdminUserDetailEvent extends Equatable {
  const AdminUserDetailEvent();
}

class AdminUserDetailLoadRequested extends AdminUserDetailEvent {
  final String adminId;
  const AdminUserDetailLoadRequested(this.adminId);
}

class AdminUserDetailRefreshRequested extends AdminUserDetailEvent {}
```

#### UI Requirements

**Layout - 3 sections**:

1. **User Info Card**:
   - Username (large)
   - Email
   - Status badge (Active/Inactive)
   - Created date
   - Last login timestamp
   - Total login count

2. **Login Statistics Card**:
   - Successful logins (total)
   - Failed login attempts (last 30 days)
   - Average logins per week
   - Most common login time (hour of day)
   - Most common login location (IP/location)
   - Login streak (consecutive days)

3. **Login History Table**:
   - Timestamp
   - Status (Success/Failed badge)
   - IP Address
   - User Agent (truncated, tooltip for full)
   - Location (from IP geolocation, optional)
   - Duration (session length for successful logins)
   - Pagination (last 100 attempts)

**Features**:
- **Real-time Data**: Refresh button
- **Export**: Export login history to CSV
- **Filter**: Show all/success/failed attempts
- **Search**: Filter by IP address
- **Security Alert**: Highlight suspicious patterns

**Security Alerts**:
- Multiple failed attempts from same IP (>5 in 1 hour)
- Login from new country/location
- Unusual login time (3-5 AM)

#### API Endpoints
- `GET /admin/api/admin-users/:id` - Admin user details
- `GET /admin/api/admin-users/:id/login-history?page=1&limit=100`
- `GET /admin/api/admin-users/:id/login-stats`

---

### 7. Site Configuration Screen

**Goal**: Manage registry configuration settings

#### BLoC Implementation

**ConfigBloc States**:
```dart
abstract class ConfigState extends Equatable {
  const ConfigState();
}

class ConfigInitial extends ConfigState {}

class ConfigLoading extends ConfigState {}

class ConfigLoaded extends ConfigState {
  final SiteConfig config;
  const ConfigLoaded(this.config);
}

class ConfigSaving extends ConfigState {
  final SiteConfig config;
  const ConfigSaving(this.config);
}

class ConfigSaved extends ConfigState {
  final SiteConfig config;
  const ConfigSaved(this.config);
}

class ConfigError extends ConfigState {
  final String message;
  const ConfigError(this.message);
}
```

**ConfigBloc Events**:
```dart
abstract class ConfigEvent extends Equatable {
  const ConfigEvent();
}

class ConfigLoadRequested extends ConfigEvent {}

class ConfigSaveRequested extends ConfigEvent {
  final SiteConfig config;
  const ConfigSaveRequested(this.config);
}

class ConfigFieldChanged extends ConfigEvent {
  final String field;
  final dynamic value;
  const ConfigFieldChanged(this.field, this.value);
}
```

#### UI Requirements

**Configuration Categories**:

1. **General Settings**:
   - Registry Name (display name)
   - Base URL (read-only, from env)
   - Listen Address (read-only, from env)
   - Enable Upstream Proxy (toggle)
   - Upstream URL (text field, default: https://pub.dev)

2. **Authentication Settings**:
   - Require Download Auth (toggle)
   - Session TTL (hours, range: 1-168)
   - Admin Session TTL (hours, range: 1-24)
   - Allow User Registration (toggle)

3. **Storage Settings**:
   - Storage Type (read-only: Local/S3)
   - Storage Path (read-only, from env)
   - S3 Bucket (read-only, from env if S3)
   - Cache Path (read-only, from env)
   - Max Package Size (MB, range: 1-100)

4. **Database Settings**:
   - Database Type (read-only: SQLite/PostgreSQL)
   - Database URL (read-only, from env, masked)
   - Connection Pool Size (read-only, for PostgreSQL)

5. **Analytics Settings**:
   - Track Downloads (toggle)
   - Track IP Addresses (toggle)
   - Retention Period (days, range: 7-365)

**Layout**:
- Grouped by category with expansion tiles
- Form fields with validation
- Save button (enabled only when changed)
- Reset button (revert to current)
- Status indicator (Saved, Saving, Error)

**Validation Rules**:
- Registry name: 3-50 characters
- TTL: 1-168 hours for users, 1-24 for admin
- Max package size: 1-100 MB
- Retention period: 7-365 days
- Upstream URL: Valid HTTP(S) URL

**Persistence**:
- Settings stored in database (new table: `site_config`)
- Environment variables override database settings
- Shows which settings are overridden by env vars

#### API Endpoints
- `GET /admin/api/config` - Get current configuration
- `POST /admin/api/config` - Update configuration
- `GET /admin/api/config/env` - Get env variable status (🆕 new endpoint)

---

## Data Models

### PackageInfo
```dart
class PackageInfo extends Equatable {
  final String name;
  final String latestVersion;
  final int versionCount;
  final DateTime publishedAt;
  final String? publisher; // User email
  final int downloadCount;
  final bool isDiscontinued;
  final String? replacedBy;
  final PackageSource source; // local or cached

  const PackageInfo({...});
}

enum PackageSource { local, cached }
```

### UserInfo
```dart
class UserInfo extends Equatable {
  final String id;
  final String email;
  final String? name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final int tokenCount;
  final int packageCount; // Packages owned

  const UserInfo({...});
}
```

### AdminUserInfo
```dart
class AdminUserInfo extends Equatable {
  final String id;
  final String username;
  final String? email;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final int loginCount;
  final int failedLoginCount; // Last 30 days

  const AdminUserInfo({...});
}
```

### LoginAttempt
```dart
class LoginAttempt extends Equatable {
  final DateTime timestamp;
  final bool success;
  final String ipAddress;
  final String userAgent;
  final String? location; // Optional geolocation
  final Duration? sessionDuration; // For successful logins

  const LoginAttempt({...});
}
```

### SiteConfig
```dart
class SiteConfig extends Equatable {
  // General
  final String registryName;
  final bool enableUpstreamProxy;
  final String upstreamUrl;

  // Auth
  final bool requireDownloadAuth;
  final int sessionTtlHours;
  final int adminSessionTtlHours;
  final bool allowUserRegistration;

  // Storage
  final int maxPackageSizeMb;

  // Analytics
  final bool trackDownloads;
  final bool trackIpAddresses;
  final int retentionDays;

  const SiteConfig({...});
}
```

---

## Implementation Plan

### Phase 1: BLoC Infrastructure ✅ COMPLETE
1. ✅ Set up BLoC provider structure in app.dart
2. ✅ Create base BLoC classes (dashboard, packages, users, admin_users, config)
3. ✅ Create data models (PackageInfo, UserInfo, AdminUserInfo, SiteConfig, etc.)
4. ✅ Set up equatable for all models
5. ✅ Create API client methods for all endpoints

### Phase 2: Dashboard Refactor ✅ COMPLETE
1. ✅ Create DashboardBloc with states/events
2. ✅ Refactor DashboardScreen to use BlocBuilder
3. ✅ Add recent activity feed
4. ✅ Implement refresh mechanism
5. ✅ Add loading/error states

### Phase 3: Package Management ✅ COMPLETE
1. ✅ Create PackagesBloc with states/events
2. ✅ Implement Local Packages screen (search, pagination, delete, discontinue)
3. ✅ Implement Cached Packages screen (view/clear cache)

### Phase 4: User Management ✅ COMPLETE
1. ✅ Create UsersBloc
2. ✅ Implement Users screen (filter, search, activate/deactivate, view tokens)
3. ✅ Create AdminUsersBloc
4. ✅ Implement Admin Users screen (read-only list, CLI info)
5. ✅ Implement Admin User Detail screen (login history, statistics)

### Phase 5: Configuration ✅ COMPLETE
1. ✅ Create ConfigBloc
2. ✅ Implement Site Configuration screen (form with save/reset)

### Phase 6: Polish & Testing (In Progress)
1. ✅ Implement error handling
2. ✅ Add confirmation dialogs
3. ✅ Create model unit tests (20 tests)
4. 🔨 Write BLoC unit tests (blocked by web package dependency)
5. 🔨 Write widget tests
6. 🔨 E2E testing with chrome-devtools MCP
7. 🔨 Performance optimization
8. 🔨 Accessibility improvements

---

## Testing Strategy

### Unit Tests (BLoC)
Each BLoC must have comprehensive tests:
```dart
// Example: local_packages_bloc_test.dart
void main() {
  group('LocalPackagesBloc', () {
    late LocalPackagesBloc bloc;
    late MockAdminApiClient apiClient;

    setUp(() {
      apiClient = MockAdminApiClient();
      bloc = LocalPackagesBloc(apiClient: apiClient);
    });

    blocTest<LocalPackagesBloc, LocalPackagesState>(
      'emits [Loading, Loaded] when LocalPackagesLoadRequested succeeds',
      build: () => bloc,
      act: (bloc) => bloc.add(const LocalPackagesLoadRequested()),
      expect: () => [
        LocalPackagesLoading(),
        isA<LocalPackagesLoaded>(),
      ],
    );

    // More tests...
  });
}
```

### Widget Tests
Test screen widgets with mock BLoCs:
```dart
// Example: local_packages_screen_test.dart
void main() {
  testWidgets('displays loading indicator', (tester) async {
    final bloc = MockLocalPackagesBloc();
    when(() => bloc.state).thenReturn(LocalPackagesLoading());

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const LocalPackagesScreen(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
```

### Integration Tests (E2E with chrome-devtools MCP)
```dart
// Test complete user flows
void main() {
  test('Admin can delete package', () async {
    // 1. Login to admin panel
    // 2. Navigate to local packages
    // 3. Click delete on test package
    // 4. Confirm deletion
    // 5. Verify package removed
  });
}
```

---

## UI/UX Guidelines

### Design System

**Colors** (Material 3):
- Primary: Blue (`Colors.blue`)
- Error: Red (`Colors.red`)
- Success: Green (`Colors.green`)
- Warning: Orange (`Colors.orange`)

**Typography**:
- Headlines: `headlineMedium`, `headlineSmall`
- Body: `bodyLarge`, `bodyMedium`
- Captions: `bodySmall`

**Spacing**:
- Consistent 8px grid
- Card padding: 16px
- Section spacing: 24px

### Component Library

**Reusable Widgets**:
1. `StatCard` - Dashboard metric cards
2. `DataTableCard` - Tables with pagination
3. `LoadingIndicator` - Circular progress with message
4. `ErrorView` - Error state with retry button
5. `EmptyState` - Empty list placeholder
6. `ConfirmDialog` - Reusable confirmation dialogs
7. `FilterChipGroup` - Filter chip selection
8. `PaginationControls` - Next/prev buttons with page info

### Loading States
- Use shimmer loading for tables
- Show spinner for actions (delete, save)
- Disable buttons during loading
- Show success/error snackbars

### Error Handling
- Show user-friendly error messages
- Provide retry options
- Log detailed errors to console
- Handle network errors gracefully

---

## API Endpoints Summary

### Existing (Implemented)
- ✅ `POST /admin/api/auth/login`
- ✅ `POST /admin/api/auth/logout`
- ✅ `GET /admin/api/auth/me`
- ✅ `GET /admin/api/stats`
- ✅ `GET /admin/api/analytics/packages-created`
- ✅ `GET /admin/api/analytics/downloads`
- ✅ `GET /admin/api/packages/local`
- ✅ `GET /admin/api/packages/cached`
- ✅ `GET /admin/api/users`
- ✅ `GET /admin/api/admin-users`
- ✅ `GET /admin/api/admin-users/:id/login-history`

### To Be Implemented
- 🔨 `GET /admin/api/activity` - Recent activity feed
- 🔨 `DELETE /admin/api/packages/:name` - Delete local package
- 🔨 `POST /admin/api/packages/:name/discontinue` - Discontinue package
- 🔨 `DELETE /admin/api/packages/cached/:name` - Clear cached package
- 🔨 `DELETE /admin/api/packages/cached` - Clear all cache
- 🔨 `POST /admin/api/users/:id/activate` - Activate user
- 🔨 `POST /admin/api/users/:id/deactivate` - Deactivate user
- 🔨 `DELETE /admin/api/users/:id` - Delete user
- 🔨 `GET /admin/api/users/:id/tokens` - List user tokens
- 🔨 `DELETE /admin/api/users/:id/tokens/:label` - Revoke user token
- 🔨 `GET /admin/api/admin-users/:id` - Admin user detail
- 🔨 `GET /admin/api/admin-users/:id/login-stats` - Login statistics
- 🔨 `GET /admin/api/config` - Get configuration
- 🔨 `POST /admin/api/config` - Update configuration
- 🔨 `GET /admin/api/config/env` - Environment variable status

---

## Success Criteria

### Code Quality
- [ ] All BLoCs have >80% test coverage
- [ ] All screens have widget tests
- [ ] No linter warnings
- [ ] Proper error handling throughout
- [ ] Consistent code style

### Functionality
- [ ] All 7 screens fully implemented
- [ ] All CRUD operations working
- [ ] Search and filtering functional
- [ ] Pagination working correctly
- [ ] Real-time updates via BLoC streams

### Performance
- [ ] Initial load < 2 seconds
- [ ] Table rendering < 500ms for 100 rows
- [ ] Search debouncing working (500ms)
- [ ] No memory leaks (BLoC disposal)
- [ ] Smooth animations (60 FPS)

### User Experience
- [ ] Loading states everywhere
- [ ] Error states with retry
- [ ] Success feedback (snackbars)
- [ ] Confirmation dialogs for destructive actions
- [ ] Responsive design (desktop focus)
- [ ] Keyboard navigation support

---

## Appendix

### BLoC Best Practices
1. **Single Responsibility**: One BLoC per feature
2. **Immutable State**: Use `Equatable` for all states
3. **Event-Driven**: User actions → Events → States
4. **Async Handling**: Use `async*` generators
5. **Error Handling**: Always catch and emit error states
6. **Resource Cleanup**: Dispose in `close()` method
7. **Testing**: Test all state transitions

### Common Patterns

**Pagination**:
```dart
class PaginatedState<T> extends Equatable {
  final List<T> items;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
}
```

**Search with Debouncing**:
```dart
EventTransformer<E> debounce<E>(Duration duration) {
  return (events, mapper) => events
      .debounceTime(duration)
      .switchMap(mapper);
}

on<SearchChanged>(
  (event, emit) async {
    // Handle search
  },
  transformer: debounce(const Duration(milliseconds: 500)),
);
```

**Optimistic Updates**:
```dart
on<ItemDeleteRequested>((event, emit) async {
  final previousState = state;

  // Optimistically update UI
  emit(ItemDeleting(event.id));

  try {
    await apiClient.deleteItem(event.id);
    emit(ItemDeleted(event.id));
  } catch (e) {
    // Rollback on error
    emit(previousState);
    emit(ItemDeleteError(e.toString()));
  }
});
```

---

## Changelog

**2026-01-27 v2.0**: Admin Panel Implementation PRD
- Complete rewrite focused on admin panel development
- BLoC state management architecture
- Detailed specifications for 7 admin screens
- Data models and API endpoint definitions
- Implementation plan with phases
- Testing strategy and best practices

**2026-01-27 v1.0**: Initial PRD
- Core features and architecture documented
- Analytics dashboard implemented
- Token scopes and authorization system
