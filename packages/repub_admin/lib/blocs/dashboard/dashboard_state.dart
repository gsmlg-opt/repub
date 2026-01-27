import 'package:equatable/equatable.dart';
import '../../models/dashboard_stats.dart';

/// Base class for all dashboard states.
abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

/// State when dashboard data is being loaded.
class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

/// State when dashboard data is successfully loaded.
class DashboardLoaded extends DashboardState {
  final DashboardStats stats;

  const DashboardLoaded(this.stats);

  @override
  List<Object?> get props => [stats];
}

/// State when dashboard data loading fails.
class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
