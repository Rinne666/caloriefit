import stepBaselineTest from './StepBaseline.test';
import activityRepositoryTest from './ActivityRepository.test';
import bodyDataTest from './BodyData.test';

export default function testsuite() {
  stepBaselineTest();
  activityRepositoryTest();
  bodyDataTest();
}
