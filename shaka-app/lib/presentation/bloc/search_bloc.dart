import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/spot_models.dart';
import '../../data/repositories/spot_repository.dart';

// Events
abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchSpots extends SearchEvent {
  final double lat;
  final double lon;
  final String date;
  final int radiusKm;

  const SearchSpots({
    required this.lat,
    required this.lon,
    required this.date,
    this.radiusKm = 50,
  });

  @override
  List<Object?> get props => [lat, lon, date, radiusKm];
}

class LoadSpotDetail extends SearchEvent {
  final String spotId;
  final String date;

  const LoadSpotDetail({required this.spotId, required this.date});

  @override
  List<Object?> get props => [spotId, date];
}

class ClearSearch extends SearchEvent {}

// States
abstract class SearchState extends Equatable {
  const SearchState();

  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {}

class SearchLoading extends SearchState {}

class SearchSuccess extends SearchState {
  final SearchResponse response;

  const SearchSuccess(this.response);

  @override
  List<Object?> get props => [response];
}

class SpotDetailLoading extends SearchState {}

class SpotDetailSuccess extends SearchState {
  final SpotDetail spot;

  const SpotDetailSuccess(this.spot);

  @override
  List<Object?> get props => [spot];
}

class SearchError extends SearchState {
  final String message;

  const SearchError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SpotRepository _repository;

  SearchBloc(this._repository) : super(SearchInitial()) {
    on<SearchSpots>(_onSearchSpots);
    on<LoadSpotDetail>(_onLoadSpotDetail);
    on<ClearSearch>(_onClearSearch);
  }

  Future<void> _onSearchSpots(
    SearchSpots event,
    Emitter<SearchState> emit,
  ) async {
    emit(SearchLoading());
    try {
      final response = await _repository.searchSpots(
        lat: event.lat,
        lon: event.lon,
        date: event.date,
        radiusKm: event.radiusKm,
      );
      emit(SearchSuccess(response));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> _onLoadSpotDetail(
    LoadSpotDetail event,
    Emitter<SearchState> emit,
  ) async {
    emit(SpotDetailLoading());
    try {
      final spot = await _repository.getSpotDetail(
        spotId: event.spotId,
        date: event.date,
      );
      emit(SpotDetailSuccess(spot));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  void _onClearSearch(ClearSearch event, Emitter<SearchState> emit) {
    emit(SearchInitial());
  }
}
