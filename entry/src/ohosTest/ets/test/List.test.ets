import stepBaselineTest from './StepBaseline.test';
import activityRepositoryTest from './ActivityRepository.test';
import bodyDataTest from './BodyData.test';
import foodRegionTest from './FoodRegion.test';
import canvasCutoutTest from './CanvasCutout.test';

export default function testsuite() {
  stepBaselineTest();
  activityRepositoryTest();
  bodyDataTest();
  foodRegionTest();
  canvasCutoutTest();
}
