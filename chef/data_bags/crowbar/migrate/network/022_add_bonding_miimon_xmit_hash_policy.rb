def upgrade(ta, td, a, d)
  unless a["network"]["teaming"].key? "miimon"
    a["network"]["teaming"]["miimon"] = ta["network"]["teaming"]["miimon"]
  end
  unless a["network"]["teaming"].key? "xmit_hash_policy"
    a["network"]["teaming"]["xmit_hash_policy"] = ta["network"]["teaming"]["xmit_hash_policy"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["network"]["teaming"].key? "miimon"
    a["network"]["teaming"].delete "miimon"
  end
  unless ta["network"]["teaming"].key? "xmit_hash_policy"
    a["network"]["teaming"].delete "xmit_hash_policy"
  end
  return a, d
end
