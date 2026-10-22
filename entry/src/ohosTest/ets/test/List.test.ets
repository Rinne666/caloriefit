import stepBaselineTest from './StepBaseline.test';
import activityRepositoryTest from './ActivityRepository.test';
import bodyDataTest from './BodyData.test';
import foodRegionTest from './FoodRegion.test';
import canvasCutoutTest from './CanvasCutout.test';
import foodBatchTest from './FoodBatch.test';
import boardCanvasTest from './BoardCanvas.test';
import fixRegressionTest from './FixRegression.test';

export default function testsuite() {
  stepBaselineTest();
  activityRepositoryTest();
  bodyDataTest();
  foodRegionTest();
  canvasCutoutTest();
  foodBatchTest();
  boardCanvasTest();
  fixRegressionTest();
}
