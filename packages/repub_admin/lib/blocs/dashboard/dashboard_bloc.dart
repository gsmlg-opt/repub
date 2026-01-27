import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/admin_api_client.dart';
import '../../models/dashboard_stats.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// BLoC that manages dashboard state and handles dashboard events.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final AdminApiClient _apiClient;

  DashboardBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const DashboardInitial()) {
    on<LoadDashboard>(_onLoadDashboard);
    on<RefreshDashboard>(_onRefreshDashboard);
  }

  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    try {
      final statsData = await _apiClient.getDashboardStats();
      final stats = DashboardStats.fromJson(statsData);
      emit(DashboardLoaded(stats));
    } catch (e) {
      emit(DashboardError('Failed to load dashboard: $e'));
    }
  }

  Future<void> _onRefreshDashboard(
    RefreshDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    // Keep current data while refreshing
    if (state is DashboardLoaded) {
      try {
        final statsData = await _apiClient.getDashboardStats();
        final stats = DashboardStats.fromJson(statsData);
        emit(DashboardLoaded(stats));
      } catch (e) {
        // On refresh error, keep showing old data with error message
        emit(DashboardError('Failed to refresh: $e'));
      }
    } else {
      // If not loaded yet, treat as initial load
      add(const LoadDashboard());
    }
  }
}
