// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2018-2025, The OpenROAD Authors

#include "timingBase.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <functional>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "nesterovBase.h"
#include "placerBase.h"
#include "rsz/Resizer.hh"
#include "sta/Fuzzy.hh"
#include "utl/Logger.h"

namespace gpl {

using utl::GPL;

// TimingBase
TimingBase::TimingBase() = default;

TimingBase::TimingBase(std::shared_ptr<NesterovBaseCommon> nbc,
                       rsz::Resizer* rs,
                       utl::Logger* log)
    : TimingBase()
{
  rs_ = rs;
  nbc_ = std::move(nbc);
  log_ = log;
}

void TimingBase::initTimingOverflowChk()
{
  timingOverflowChk_.clear();
  timingOverflowChk_.resize(timingNetWeightOverflow_.size(), false);
}

bool TimingBase::isTimingNetWeightOverflow(float overflow)
{
  int intOverflow = std::round(overflow * 100);
  // exception case handling
  if (timingNetWeightOverflow_.empty()
      || intOverflow > timingNetWeightOverflow_[0]) {
    return false;
  }

  bool needTdRun = false;
  for (int i = 0; i < timingNetWeightOverflow_.size(); i++) {
    if (timingNetWeightOverflow_[i] > intOverflow) {
      if (!timingOverflowChk_[i]) {
        timingOverflowChk_[i] = true;
        needTdRun = true;
      }
      continue;
    }
    return needTdRun;
  }
  return needTdRun;
}

void TimingBase::addTimingNetWeightOverflow(int overflow)
{
  std::vector<int>::iterator it = std::find(timingNetWeightOverflow_.begin(),
                                            timingNetWeightOverflow_.end(),
                                            overflow);

  // only push overflow when the overflow is not in vector.
  if (it == timingNetWeightOverflow_.end()) {
    timingNetWeightOverflow_.push_back(overflow);
  }

  // do sort in reverse order
  std::sort(timingNetWeightOverflow_.begin(),
            timingNetWeightOverflow_.end(),
            std::greater<int>());
}

void TimingBase::setTimingNetWeightOverflows(std::vector<int>& overflows)
{
  // sort by decreasing order
  std::sort(overflows.begin(), overflows.end(), std::greater<int>());
  for (auto& overflow : overflows) {
    addTimingNetWeightOverflow(overflow);
  }
  initTimingOverflowChk();
}

void TimingBase::deleteTimingNetWeightOverflow(int overflow)
{
  std::vector<int>::iterator it = std::find(timingNetWeightOverflow_.begin(),
                                            timingNetWeightOverflow_.end(),
                                            overflow);
  // only erase overflow when the overflow is in vector.
  if (it != timingNetWeightOverflow_.end()) {
    timingNetWeightOverflow_.erase(it);
  }
}

void TimingBase::clearTimingNetWeightOverflow()
{
  timingNetWeightOverflow_.clear();
}

size_t TimingBase::getTimingNetWeightOverflowSize() const
{
  return timingNetWeightOverflow_.size();
}

void TimingBase::setTimingNetWeightMax(float max)
{
  net_weight_max_ = max;
}

void TimingBase::setDynamicWeightOptions(const DynamicWeightOptions& options)
{
  dynamic_options_ = options;
}

bool TimingBase::executeTimingDriven(bool run_journal_restore,
                                     int iter,
                                     float average_overflow,
                                     float average_overflow_unscaled)
{
  rs_->findResizeSlacks(run_journal_restore);

  if (!run_journal_restore) {
    nbc_->fixPointers();
  }

  std::vector<odb::dbNet*> candidate_nets;
  if (dynamic_options_.top_endpoints > 0) {
    candidate_nets = rs_->criticalPathNets(
        dynamic_options_.top_endpoints,
        static_cast<sta::Slack>(dynamic_options_.endpoint_slack_threshold));
  }
  if (candidate_nets.empty()) {
    sta::NetSeq worst_nets = rs_->resizeWorstSlackNets();
    candidate_nets.reserve(worst_nets.size());
    for (const sta::Net* sta_net : worst_nets) {
      odb::dbNet* db_net = rs_->staToDb(sta_net);
      if (db_net != nullptr) {
        candidate_nets.push_back(db_net);
      }
    }
  }

  std::vector<std::pair<odb::dbNet*, sta::Slack>> net_slacks;
  net_slacks.reserve(candidate_nets.size());
  for (odb::dbNet* db_net : candidate_nets) {
    auto slack_opt = rs_->resizeNetSlack(db_net);
    if (!slack_opt) {
      continue;
    }
    net_slacks.emplace_back(db_net, slack_opt.value());
  }

  if (net_slacks.empty()) {
    log_->warn(
        GPL,
        105,
        "Timing-driven: no net slacks found. Timing-driven mode disabled.");
    return false;
  }

  std::sort(net_slacks.begin(),
            net_slacks.end(),
            [](const auto& lhs, const auto& rhs) {
              return lhs.second < rhs.second;
            });

  const sta::Slack slack_min = net_slacks.front().second;
  const sta::Slack slack_max = net_slacks.back().second;
  const bool has_slack_span = std::abs(slack_max - slack_min) > 1e-12;

  log_->info(GPL, 106, "Timing-driven: worst slack {:.3g}", slack_min);

  if (sta::fuzzyInf(slack_min)) {
    log_->warn(GPL,
               102,
               "Timing-driven: no slacks found. Timing-driven mode disabled.");
    return false;
  }

  const bool dynamic_enabled = dynamic_options_.enable;
  const bool allow_dynamic
      = dynamic_enabled
        && (dynamic_options_.overflow_limit <= 0.0f
            || average_overflow_unscaled <= dynamic_options_.overflow_limit);

  const bool should_update = !dynamic_enabled
                             || dynamic_options_.update_period <= 1
                             || ((iter + 1) % dynamic_options_.update_period)
                                    == 0;

  const double length_norm
      = (dynamic_options_.length_norm > 0.0) ? dynamic_options_.length_norm
                                             : 1.0;

  float severity_ratio = 0.0f;
  float weight_boost = 1.0f;
  float coverage_boost = 1.0f;
  float effective_weight_max = dynamic_options_.weight_max;
  if (dynamic_enabled && dynamic_options_.severity_slack_norm > 0.0f) {
    const float denom = dynamic_options_.severity_slack_norm;
    if (denom > 0.0f) {
      severity_ratio = std::clamp(
          static_cast<float>(-slack_min) / denom,
          0.0f,
          dynamic_options_.severity_ratio_cap);
      const float raw_weight_boost
          = 1.0f + dynamic_options_.severity_weight_scale * severity_ratio;
      weight_boost = std::clamp(raw_weight_boost,
                                1.0f,
                                dynamic_options_.severity_weight_limit);
      const float raw_coverage_boost
          = 1.0f + dynamic_options_.severity_coverage_scale * severity_ratio;
      coverage_boost = std::clamp(raw_coverage_boost,
                                  1.0f,
                                  dynamic_options_.severity_coverage_limit);
      const float span_base = dynamic_options_.weight_max
                              - dynamic_options_.weight_min;
      if (span_base > 0.0f) {
        effective_weight_max = dynamic_options_.weight_min
                               + span_base * weight_boost;
      }
    }
  }

  float ramp = 1.0f;
  if (dynamic_options_.ramp_iterations > 0) {
    ramp = std::min(
        1.0f,
        static_cast<float>(iter + 1) / static_cast<float>(dynamic_options_.ramp_iterations));
  }

  float coverage = dynamic_options_.final_coverage_percent;
  if (dynamic_options_.final_coverage_percent
      > dynamic_options_.initial_coverage_percent) {
    const float delta = dynamic_options_.final_coverage_percent
                        - dynamic_options_.initial_coverage_percent;
    coverage = dynamic_options_.initial_coverage_percent + delta * ramp;
  }
  coverage = std::clamp(coverage, dynamic_options_.initial_coverage_percent,
                        dynamic_options_.final_coverage_percent);

  size_t coverage_count = net_slacks.size();
  if (allow_dynamic) {
    coverage_count = static_cast<size_t>(std::ceil(
        coverage / 100.0f * static_cast<float>(net_slacks.size())));
    coverage_count
        = std::clamp<size_t>(coverage_count, 1, net_slacks.size());
    if (coverage_boost > 1.0f && coverage_count < net_slacks.size()) {
      const float boosted = coverage_boost
                            * static_cast<float>(coverage_count);
      coverage_count = std::clamp<size_t>(
          static_cast<size_t>(std::ceil(boosted)),
          1,
          net_slacks.size());
    }
  }

  float slack_cutoff = slack_max;
  if (allow_dynamic && coverage_count > 0) {
    slack_cutoff = net_slacks[coverage_count - 1].second;
  }

  const double slack_norm
      = (dynamic_options_.slack_norm > 0.0)
            ? dynamic_options_.slack_norm
            : std::max(1e-12,
                       static_cast<double>(slack_cutoff - slack_min));
  const float congestion_factor_global
      = std::clamp(1.0f - dynamic_options_.congestion_alpha
                              * std::clamp(average_overflow, 0.0f, 1.0f),
                    0.0f,
                    1.0f);
  const float dynamic_span = std::max(
      0.0f, effective_weight_max - dynamic_options_.weight_min);
  const float fallback_weight_max
      = std::max(effective_weight_max, net_weight_max_);

  std::unordered_map<const odb::dbNet*, sta::Slack> slack_by_net;
  slack_by_net.reserve(net_slacks.size());
  std::unordered_set<const odb::dbNet*> strong_nets;
  for (size_t idx = 0; idx < net_slacks.size(); ++idx) {
    const auto& [db_net, slack] = net_slacks[idx];
    slack_by_net.emplace(db_net, slack);
    if (idx < coverage_count) {
      strong_nets.insert(db_net);
    }
  }

  int weighted_net_count = 0;
  for (auto& gNet : nbc_->getGNets()) {
    // default weight
    float weight = 1.0f;
    if (gNet->getGPins().size() > 1) {
      bool is_candidate = false;
      bool is_strong = false;
      double net_slack = slack_max;
      for (Net* pb_net : gNet->getPbNets()) {
        odb::dbNet* db_net = pb_net->getDbNet();
        auto it = slack_by_net.find(db_net);
        if (it == slack_by_net.end()) {
          continue;
        }
        is_candidate = true;
        net_slack = std::min(net_slack, static_cast<double>(it->second));
        if (strong_nets.find(db_net) != strong_nets.end()) {
          is_strong = true;
        }
      }

      if (!is_candidate) {
        gNet->setTimingWeight(weight);
        continue;
      }

      if (!dynamic_enabled || !should_update || !has_slack_span) {
        if (has_slack_span) {
          weight = 1 + (fallback_weight_max - 1)
                         * (slack_max - net_slack)
                         / (slack_max - slack_min);
          weighted_net_count++;
        }
      } else if (is_strong) {
        const float slack_severity = std::clamp(
            static_cast<float>(-net_slack / slack_norm), 0.0f, 1.0f);

        const int dx = gNet->ux() - gNet->lx();
        const int dy = gNet->uy() - gNet->ly();
        const double len_metric
            = std::hypot(static_cast<double>(dx), static_cast<double>(dy));
        const float length_factor
            = 0.5f
              + 0.5f
                    * std::clamp(static_cast<float>(len_metric / length_norm),
                                 0.0f,
                                 1.0f);

        const float congestion_factor = congestion_factor_global;

        weight = dynamic_options_.weight_min
                 + dynamic_span * ramp * slack_severity * length_factor
                       * congestion_factor;
        weight = std::clamp(weight,
                            dynamic_options_.weight_min,
                            effective_weight_max);
        weighted_net_count++;
      } else if (has_slack_span) {
        weight = 1 + (fallback_weight_max - 1)
                       * (slack_max - net_slack)
                       / (slack_max - slack_min);
        weighted_net_count++;
      }
    }
    gNet->setTimingWeight(weight);
    debugPrint(log_,
               GPL,
               "timing",
               1,
               "net:{} weight:{}",
               gNet->getPbNet()->getDbNet()->getConstName(),
               gNet->getTotalWeight());
  }

  debugPrint(log_,
             GPL,
             "timing",
             1,
             "Timing-driven: weighted {} nets.",
             weighted_net_count);
  return true;
}

}  // namespace gpl
