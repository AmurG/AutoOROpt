// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2018-2025, The OpenROAD Authors

#pragma once

#include <cstddef>
#include <memory>
#include <vector>

#include "rsz/Resizer.hh"

namespace rsz {
class Resizer;
}

namespace utl {
class Logger;
}

namespace gpl {

class NesterovBaseCommon;
class GNet;

class TimingBase
{
 public:
  struct DynamicWeightOptions
  {
    bool enable = true;
    float weight_min = 1.0f;
    float weight_max = 6.0f;
    float congestion_alpha = 0.7f;
    int ramp_iterations = 20;
    int update_period = 5;
    float initial_coverage_percent = 10.0f;
    float final_coverage_percent = 30.0f;
    int top_endpoints = 200;
    float endpoint_slack_threshold = 0.0f;
    double slack_norm = 5e-11;
    double length_norm = 0.0;
    float overflow_limit = 0.4f;
    float severity_slack_norm = 0.2f;
    float severity_ratio_cap = 4.0f;
    float severity_weight_scale = 0.20f;
    float severity_weight_limit = 1.8f;
    float severity_coverage_scale = 0.5f;
    float severity_coverage_limit = 2.0f;
  };

  TimingBase();
  TimingBase(std::shared_ptr<NesterovBaseCommon> nbc,
             rsz::Resizer* rs,
             utl::Logger* log);

  // check whether overflow reached the timingOverflow
  bool isTimingNetWeightOverflow(float overflow);
  void addTimingNetWeightOverflow(int overflow);
  void setTimingNetWeightOverflows(std::vector<int>& overflows);
  void deleteTimingNetWeightOverflow(int overflow);
  void clearTimingNetWeightOverflow();
  size_t getTimingNetWeightOverflowSize() const;

  void setTimingNetWeightMax(float max);
  void setDynamicWeightOptions(const DynamicWeightOptions& options);

  // updateNetWeight.
  // True: successfully reweighted gnets
  // False: no slacks found
  bool executeTimingDriven(bool run_journal_restore,
                           int iter,
                           float average_overflow,
                           float average_overflow_unscaled);

 private:
  rsz::Resizer* rs_ = nullptr;
  utl::Logger* log_ = nullptr;
  std::shared_ptr<NesterovBaseCommon> nbc_;

  std::vector<int> timingNetWeightOverflow_;
  std::vector<int> timingOverflowChk_;
  float net_weight_max_ = 5;
  DynamicWeightOptions dynamic_options_;
  void initTimingOverflowChk();
};

}  // namespace gpl
