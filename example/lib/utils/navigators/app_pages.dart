import 'package:get/get.dart';

import '../../controllers/controllers.dart';
import '../../views/views.dart';

part 'app_routes.dart';

/// Contains the list of pages or routes taken across the whole application.
/// This will prevent us in using context for navigation. And also providing
/// the blocs required in the next named routes.
///
/// [pages] : will contain all the pages in the application as a route
/// and will be used in the material app.
/// Will be ignored for test since all are static values and would not change.
class AppPages {
  static var transitionDuration = const Duration(
    milliseconds: 350,
  );

  static const initial = Routes.splash;

  static final pages = [
    GetPage<SplashView>(
      name: Routes.splash,
      transitionDuration: transitionDuration,
      page: SplashView.new,
      binding: SplashBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage<HomeView>(
      name: Routes.home,
      transitionDuration: transitionDuration,
      page: HomeView.new,
      binding: HomeBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage<AddBrokerView>(
      name: Routes.addBroker,
      transitionDuration: transitionDuration,
      page: AddBrokerView.new,
      binding: HomeBinding(),
      transition: Transition.rightToLeft,
    ),
  ];
}
