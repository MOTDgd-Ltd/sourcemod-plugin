#if defined _motdgd_included_
  #endinput
#endif
#define _motdgd_included_

native bool:MOTDgd_AddRewardHandler(String:id[32], Function:callback);
native bool:MOTDgd_RemoveRewardHandler(String:id[32]);