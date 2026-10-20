import stepBaselineTest from './StepBaseline.test';
import activityRepositoryTest from './ActivityRepository.test';

export default function testsuite() {
  stepBaselineTest();
  activityRepositoryTest();
}
